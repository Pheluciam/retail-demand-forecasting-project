"""
Load M5 raw CSVs into Azure SQL Database `raw` schema.

For each of the 3 raw tables:
  1. TRUNCATE existing rows (idempotency — safe to re-run)
  2. Read source CSV with explicit UTF-8 encoding
  3. (sales_train only) Unpivot wide → long via `pandas.melt`
  4. Bulk INSERT via SQLAlchemy + pyodbc's `fast_executemany`
  5. Verify the row count against the expected value

Run from project root with venv activated:
    python scripts/load_m5_to_azure_sql.py

Estimated runtime: 30-90 minutes total. sales_train is the bottleneck
(~59M rows through Free Serverless's 2 vCores).
"""

import os
import time
import urllib.parse
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import create_engine, text


# -----------------------------------------------------------------------------
# 1. Setup
# -----------------------------------------------------------------------------
load_dotenv()
PROJECT_ROOT = Path(__file__).parent.parent
RAW_DIR = PROJECT_ROOT / "data" / "raw"

# Expected row counts — used by post-action verification
EXPECTED_ROWS = {
    "calendar":    1_969,
    "sell_prices": 6_841_121,
    "sales_train": 59_181_090,  # 30,490 series x 1,941 days = 59,181,090 (corrected 2026-05-12 21:xx — original value had an off-by-1000 arithmetic error)
}


# -----------------------------------------------------------------------------
# 2. SQLAlchemy engine with fast_executemany enabled
# -----------------------------------------------------------------------------
# `fast_executemany=True` switches pyodbc's INSERT path from sending one row
# at a time to sending a whole chunk in one network roundtrip. This is the
# single biggest speed lever when loading pandas → SQL Server.
def build_engine():
    odbc_conn_str = (
        "DRIVER={ODBC Driver 17 for SQL Server};"
        f"SERVER={os.getenv('AZURE_SQL_SERVER')};"
        f"DATABASE={os.getenv('AZURE_SQL_DATABASE')};"
        f"UID={os.getenv('AZURE_SQL_USER')};"
        f"PWD={os.getenv('AZURE_SQL_PASSWORD')};"
        "Encrypt=yes;"
        "TrustServerCertificate=no;"
        "Connection Timeout=90;"
    )
    quoted = urllib.parse.quote_plus(odbc_conn_str)
    return create_engine(
        f"mssql+pyodbc:///?odbc_connect={quoted}",
        fast_executemany=True,
    )


engine = build_engine()


# -----------------------------------------------------------------------------
# 3. Helper functions
# -----------------------------------------------------------------------------
def truncate_table(table_name: str) -> None:
    """Delete every row in `raw.<table_name>` quickly. Idempotent re-runs."""
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE TABLE raw.{table_name}"))
    print(f"  Truncated raw.{table_name}")


def insert_dataframe_chunked(
    df: pd.DataFrame,
    table_name: str,
    chunksize: int = 50_000,
    progress_every_n_chunks: int = 10,
) -> None:
    """
    Insert a DataFrame into raw.<table_name> in chunks, printing progress.

    fast_executemany is already configured on the engine — we don't need
    `method='multi'`. We chunk ourselves (rather than letting to_sql
    chunk internally) so we can print progress.
    """
    total = len(df)
    print(f"  Inserting {total:,} rows into raw.{table_name} "
          f"(chunksize={chunksize:,})...")
    start = time.time()
    chunk_idx = 0
    for i in range(0, total, chunksize):
        chunk = df.iloc[i:i + chunksize]
        chunk.to_sql(
            name=table_name,
            con=engine,
            schema="raw",
            if_exists="append",
            index=False,
            method=None,   # not 'multi' — fast_executemany handles the batching
        )
        chunk_idx += 1
        # Print progress on first chunk, every N chunks, and on last chunk
        if chunk_idx == 1 or chunk_idx % progress_every_n_chunks == 0 \
                or i + chunksize >= total:
            done = min(i + chunksize, total)
            elapsed = time.time() - start
            rate = done / elapsed if elapsed > 0 else 0
            pct = 100 * done / total
            eta_s = (total - done) / rate if rate > 0 else 0
            print(f"    {done:>11,} / {total:>11,} ({pct:5.1f}%)"
                  f"   {rate:>8,.0f} rows/sec   ETA {eta_s/60:5.1f} min")
    print(f"  INSERT complete. Elapsed: {(time.time()-start)/60:.1f} min")


def verify_row_count(table_name: str, expected: int) -> None:
    """Count rows in the target table and compare to expected. Raise on mismatch."""
    with engine.connect() as conn:
        actual = conn.execute(
            text(f"SELECT COUNT(*) FROM raw.{table_name}")
        ).scalar()
    status = "OK" if actual == expected else "MISMATCH"
    print(f"  Verification: raw.{table_name} has {actual:,} rows "
          f"(expected {expected:,}) — {status}")
    if actual != expected:
        raise ValueError(
            f"Row count mismatch for raw.{table_name}: "
            f"got {actual:,}, expected {expected:,}"
        )


# -----------------------------------------------------------------------------
# 4. Per-table loaders
# -----------------------------------------------------------------------------
def load_calendar() -> None:
    print("\n=== calendar ===")
    truncate_table("calendar")
    df = pd.read_csv(RAW_DIR / "calendar.csv", encoding="utf-8")
    print(f"  CSV shape: {df.shape[0]:,} rows x {df.shape[1]:,} cols")
    insert_dataframe_chunked(df, "calendar", chunksize=2_000)
    verify_row_count("calendar", expected=EXPECTED_ROWS["calendar"])


def load_sell_prices() -> None:
    print("\n=== sell_prices ===")
    truncate_table("sell_prices")
    df = pd.read_csv(RAW_DIR / "sell_prices.csv", encoding="utf-8")
    print(f"  CSV shape: {df.shape[0]:,} rows x {df.shape[1]:,} cols")
    insert_dataframe_chunked(df, "sell_prices", chunksize=50_000)
    verify_row_count("sell_prices", expected=EXPECTED_ROWS["sell_prices"])


def load_sales_train() -> None:
    print("\n=== sales_train (wide-to-long unpivot) ===")
    truncate_table("sales_train")

    csv_path = RAW_DIR / "sales_train_evaluation.csv"
    print(f"  Reading wide CSV: {csv_path.name}")
    df_wide = pd.read_csv(csv_path, encoding="utf-8")
    print(f"  Wide shape:  {df_wide.shape[0]:,} rows x {df_wide.shape[1]:,} cols")

    # Pre-flight: sanity-check column count before melting
    id_cols = ["id", "item_id", "dept_id", "cat_id", "store_id", "state_id"]
    day_cols = [c for c in df_wide.columns if c.startswith("d_")]
    print(f"  Found {len(day_cols)} day columns (expected 1,941)")
    if len(day_cols) != 1_941:
        raise ValueError(
            f"Day column count mismatch: got {len(day_cols)}, expected 1,941"
        )

    print("  Melting wide -> long via pandas.melt...")
    df_long = df_wide.melt(
        id_vars=id_cols,
        value_vars=day_cols,
        var_name="d",
        value_name="sales",
    )
    del df_wide  # free ~600 MB before the long DataFrame builds

    print(f"  Long shape:  {df_long.shape[0]:,} rows x {df_long.shape[1]:,} cols")
    insert_dataframe_chunked(df_long, "sales_train", chunksize=50_000)
    verify_row_count("sales_train", expected=EXPECTED_ROWS["sales_train"])


# -----------------------------------------------------------------------------
# 5. Main
# -----------------------------------------------------------------------------
def main() -> None:
    print("=== M5 -> Azure SQL load ===")
    print("(If the database has auto-paused, the first operation may take 30-60s...)")
    print("Estimated total runtime: 30-90 minutes (dominated by sales_train).\n")
    overall_start = time.time()

    load_calendar()
    load_sell_prices()
    load_sales_train()

    elapsed_min = (time.time() - overall_start) / 60
    print(f"\n=== All loads complete. Total elapsed: {elapsed_min:.1f} minutes. ===")


if __name__ == "__main__":
    main()
