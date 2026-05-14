"""
Extract M5 raw tables from Azure SQL Database into Snowflake RAW schema.

Pulls a date-bounded slice of each of the three raw tables (calendar,
sell_prices, sales_train) out of Azure SQL and lands it in Snowflake's
RETAIL_DB.RAW schema. Same script handles both modes:

  - Backfill mode:    wide --start-date / --end-date window, run once.
  - Incremental mode: --start-date == --end-date (single day), run on a
                      schedule (Airflow in Phase 3).

Idempotent: for each table, DELETEs any rows in the destination matching
the date window BEFORE inserting the fresh extract. Safe to re-run any
date slice -- duplicates are impossible.

The script joins every Azure SQL query through `raw.calendar`, because
two of the three source tables encode date differently:
  - calendar     has a real `date` column
  - sales_train  has only `d_1`..`d_1941` codes  -> JOIN to calendar.d
  - sell_prices  has only `wm_yr_wk`              -> JOIN to calendar.wm_yr_wk

Usage (PowerShell, venv activated):

    # Single day (what Airflow will call):
    python scripts/extract_azure_to_snowflake.py --run-date 2014-03-15

    # Date range (one-shot backfill):
    python scripts/extract_azure_to_snowflake.py \
        --start-date 2011-01-29 --end-date 2013-12-31

Reads connection details from .env (gitignored).

CLI CONTRACT NOTE -- DO NOT change the --run-date / --start-date / --end-date
flag names or their accepted formats without also updating
airflow/dags/m5_daily_extract.py, which imports this module and invokes
main() with a synthesised sys.argv. A flag rename here will silently break
the DAG at run time (not parse time).
"""

import argparse
import logging
import os
import sys
import time
from datetime import date

import pandas as pd
import snowflake.connector
from dotenv import load_dotenv
from snowflake.connector.pandas_tools import write_pandas


# -----------------------------------------------------------------------------
# 1. Logging -- single stream to stdout, ISO timestamps, level prefix.
# -----------------------------------------------------------------------------
# Why logging over print(): rotatable, leveled (INFO/WARNING/ERROR), and
# Airflow captures it cleanly in Phase 3. Same pattern works for ad-hoc
# PowerShell runs now.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-7s  %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    stream=sys.stdout,
)
log = logging.getLogger("extract_azure_to_snowflake")


# -----------------------------------------------------------------------------
# 2. Command-line arguments.
# -----------------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract M5 raw tables from Azure SQL into Snowflake "
                    "RETAIL_DB.RAW for a given date window.",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument(
        "--run-date",
        type=date.fromisoformat,
        help="Single date to extract (YYYY-MM-DD). Equivalent to "
             "--start-date X --end-date X.",
    )
    mode.add_argument(
        "--start-date",
        type=date.fromisoformat,
        help="Start of the inclusive date window (YYYY-MM-DD). "
             "Requires --end-date.",
    )
    parser.add_argument(
        "--end-date",
        type=date.fromisoformat,
        help="End of the inclusive date window (YYYY-MM-DD). "
             "Required if --start-date is given.",
    )
    parser.add_argument(
        "--tables",
        nargs="+",
        default=["calendar", "sell_prices", "sales_train"],
        choices=["calendar", "sell_prices", "sales_train"],
        help="Subset of tables to extract. Defaults to all three. "
             "Useful during dev: --tables calendar to smoke-test first.",
    )
    args = parser.parse_args()

    if args.run_date is not None:
        args.start_date = args.run_date
        args.end_date = args.run_date
    if args.end_date is None:
        parser.error("--end-date is required when --start-date is given.")
    if args.end_date < args.start_date:
        parser.error("--end-date must be on or after --start-date.")
    return args


# -----------------------------------------------------------------------------
# 3. .env loading + required-var pre-flight.
# -----------------------------------------------------------------------------
REQUIRED_ENV_VARS = [
    "AZURE_SQL_SERVER", "AZURE_SQL_DATABASE",
    "AZURE_SQL_USER",   "AZURE_SQL_PASSWORD",
    "SNOWFLAKE_ACCOUNT", "SNOWFLAKE_USER", "SNOWFLAKE_PASSWORD",
    "SNOWFLAKE_WAREHOUSE", "SNOWFLAKE_DATABASE",
    "SNOWFLAKE_SCHEMA", "SNOWFLAKE_ROLE",
]


def load_and_check_env() -> None:
    load_dotenv()
    missing = [v for v in REQUIRED_ENV_VARS if not os.getenv(v)]
    if missing:
        log.error("Missing required env vars in .env: %s", missing)
        sys.exit(1)


# -----------------------------------------------------------------------------
# 4. Connection helpers.
# -----------------------------------------------------------------------------
def connect_azure_sql():
    """SQLAlchemy engine for Azure SQL. Mirrors Phase 1 loader settings."""
    import urllib.parse
    from sqlalchemy import create_engine

    odbc_conn_str = (
        "DRIVER={ODBC Driver 17 for SQL Server};"
        f"SERVER={os.getenv('AZURE_SQL_SERVER')};"
        f"DATABASE={os.getenv('AZURE_SQL_DATABASE')};"
        f"UID={os.getenv('AZURE_SQL_USER')};"
        f"PWD={os.getenv('AZURE_SQL_PASSWORD')};"
        "Encrypt=yes;"                # TLS in transit
        "TrustServerCertificate=no;"  # validate the server cert
    )
    quoted = urllib.parse.quote_plus(odbc_conn_str)
    # `timeout` here is pyodbc's login-timeout kwarg, in seconds. Passing it
    # via connect_args is more reliable than embedding "Connection Timeout="
    # in the ODBC string -- some driver/pyodbc combos silently ignore the
    # string form (Invalid connection string attribute), which is what
    # caused the 16-second login-timeout failure on cold-start wake.
    engine = create_engine(
        f"mssql+pyodbc:///?odbc_connect={quoted}",
        connect_args={"timeout": 90},   # survive Free Serverless auto-pause wake
    )
    log.info("Built Azure SQL engine -> server=%s, database=%s",
             os.getenv("AZURE_SQL_SERVER"), os.getenv("AZURE_SQL_DATABASE"))
    return engine


# -----------------------------------------------------------------------------
# 4a. Azure SQL cold-start wake helper.
# -----------------------------------------------------------------------------
# Free Serverless auto-pauses after ~1 hour idle. The first cold connect of
# a session can fail in one of two transient ways that the 90s
# connect_args["timeout"] does NOT cover, because the failure isn't a
# client-side timeout -- the server responds immediately with an error code:
#
#   * 40613 -- "Database '...' is not currently available. Please retry the
#              connection later." Gateway signal that wake-up is in progress.
#              Hit this on the very first connect of the 2026-05-14 backfill.
#   * 40197 -- "The service is busy / encountered an error processing your
#              request." Same family -- transient, retry-safe.
#
# Manual fix at the time: Start-Sleep -Seconds 45 then re-run. This helper
# automates that pattern. It's particularly important once Airflow wraps
# this script: every scheduled run after overnight idle will hit a cold
# Azure SQL, and absorbing the wake here is cheaper than burning an entire
# Airflow task retry (each attempt re-imports the script, re-reads .env,
# re-opens Snowflake -- ~30s of wasted setup per retry).

def wake_azure_sql(engine, retries: int = 3, delay_sec: int = 45) -> None:
    """Touch Azure SQL with a cheap SELECT 1 until it answers cleanly.

    Retries on the two known cold-start transient SQL error codes:
        * 40613 -- database paused, waking up
        * 40197 -- service busy

    Re-raises the original exception unchanged for any other failure
    (auth, network, firewall, etc.) so real errors aren't masked by the
    retry loop.
    """
    # Local import: keeps top-of-file imports tidy and makes the helper
    # self-contained for anyone reading it in isolation.
    from sqlalchemy import text

    transient_codes = ("40613", "40197")

    for attempt in range(1, retries + 1):
        try:
            with engine.connect() as conn:
                conn.execute(text("SELECT 1"))
            log.info("Azure SQL wake OK (attempt %d/%d).", attempt, retries)
            return
        except Exception as e:  # noqa: BLE001 -- intentional broad catch
            msg = str(e)
            is_transient = any(code in msg for code in transient_codes)

            if not is_transient:
                # Real error -- don't waste retries, surface it immediately.
                log.error("Azure SQL wake failed with non-transient error: %s",
                          msg.split("\n")[0])
                raise

            if attempt == retries:
                log.error(
                    "Azure SQL still unavailable after %d attempts. "
                    "Last error: %s", retries, msg.split("\n")[0],
                )
                raise

            log.warning(
                "Azure SQL transient (attempt %d/%d, codes %s) -- "
                "sleeping %ds before retry. Detail: %s",
                attempt, retries, "/".join(transient_codes),
                delay_sec, msg.split("\n")[0],
            )
            time.sleep(delay_sec)


def connect_snowflake():
    """Native Snowflake connector (required by write_pandas)."""
    conn = snowflake.connector.connect(
        account=os.getenv("SNOWFLAKE_ACCOUNT"),
        user=os.getenv("SNOWFLAKE_USER"),
        password=os.getenv("SNOWFLAKE_PASSWORD"),
        warehouse=os.getenv("SNOWFLAKE_WAREHOUSE"),
        database=os.getenv("SNOWFLAKE_DATABASE"),
        schema=os.getenv("SNOWFLAKE_SCHEMA"),
        role=os.getenv("SNOWFLAKE_ROLE"),
        login_timeout=60,
        network_timeout=120,
        client_session_keep_alive=False,
    )
    log.info("Connected to Snowflake -> account=%s, role=%s, warehouse=%s, "
             "database=%s, schema=%s",
             os.getenv("SNOWFLAKE_ACCOUNT"),
             os.getenv("SNOWFLAKE_ROLE"),
             os.getenv("SNOWFLAKE_WAREHOUSE"),
             os.getenv("SNOWFLAKE_DATABASE"),
             os.getenv("SNOWFLAKE_SCHEMA"))
    return conn


# -----------------------------------------------------------------------------
# 5. Shared helpers used by every per-table loader.
# -----------------------------------------------------------------------------
# 100k rows of sales_train (8 narrow cols) is ~10 MB -- bounded RAM regardless
# of how big the date window is.
CHUNKSIZE = 100_000


def get_date_mapping(engine, start_date: date, end_date: date) -> pd.DataFrame:
    """Pull (date, d, wm_yr_wk) from raw.calendar for the window."""
    sql = """
        SELECT [date], d, wm_yr_wk
        FROM   raw.calendar
        WHERE  [date] BETWEEN ? AND ?
    """
    df = pd.read_sql(sql, engine, params=(start_date.isoformat(),
                                          end_date.isoformat()))
    log.info("Calendar mapping resolved -> %d dates, %d distinct fiscal weeks",
             len(df), df["wm_yr_wk"].nunique())
    return df


def write_chunks_to_snowflake(read_iter, conn_sf, dest_table: str) -> int:
    """Consume an iterator of pandas chunks; write each via write_pandas."""
    total = 0
    chunk_idx = 0
    t0 = time.time()
    for chunk in read_iter:
        chunk_idx += 1
        chunk.columns = [c.upper() for c in chunk.columns]
        success, nchunks, nrows, _ = write_pandas(
            conn_sf,
            chunk,
            table_name=dest_table,
            database=os.getenv("SNOWFLAKE_DATABASE"),
            schema=os.getenv("SNOWFLAKE_SCHEMA"),
            quote_identifiers=False,
            auto_create_table=False,
            overwrite=False,
        )
        if not success:
            raise RuntimeError(
                f"write_pandas reported failure on chunk {chunk_idx} "
                f"into {dest_table} (rows={len(chunk)})"
            )
        total += nrows
        elapsed = time.time() - t0
        rate = total / elapsed if elapsed > 0 else 0
        log.info("  chunk %3d -> %s: +%s rows  (total %s, %.0f rows/sec)",
                 chunk_idx, dest_table, f"{nrows:,}", f"{total:,}", rate)
    return total


def delete_destination_slice(conn_sf, sql: str, params: tuple) -> int:
    """Run a parameterised DELETE on Snowflake. No SQL injection surface."""
    with conn_sf.cursor() as cur:
        cur.execute(sql, params)
        n = cur.rowcount
    log.info("  pre-DELETE removed %s existing rows from destination",
             f"{n:,}")
    return n


def in_clause_placeholders(values, marker: str = "?") -> str:
    """Comma-separated placeholders for IN (...). '?' for pyodbc, '%s' for SF.

    NB: Azure SQL has a hard limit of 2,100 parameters per query.
    Our largest IN list at full M5 history is 1,941 d values for sales_train
    — within limits, but close. If the dataset is ever extended beyond
    ~2,000 dates, switch to a temp-table join instead of an IN list.
    """
    return ",".join([marker] * len(values))


def verify_parity(table_name: str, src_count: int, dest_written: int) -> None:
    """Source count vs written count. Raise on mismatch -- fail loud."""
    if src_count == dest_written:
        log.info("  Verification: %s parity OK (%s rows)",
                 table_name, f"{src_count:,}")
    else:
        raise ValueError(
            f"Row count mismatch for {table_name}: "
            f"source had {src_count:,}, wrote {dest_written:,}"
        )


# -----------------------------------------------------------------------------
# 6. Per-table loaders.
# -----------------------------------------------------------------------------
# Each loader follows the same five-step shape:
#   (a) build the date-filtered source SQL
#   (b) pre-flight: count rows in source
#   (c) pre-DELETE the slice in Snowflake (idempotency)
#   (d) stream-read in CHUNKSIZE chunks, write each to Snowflake
#   (e) post-action: source count == written count

def extract_calendar(engine_az, conn_sf,
                     start_date: date, end_date: date) -> None:
    log.info("=== calendar ===")
    src_sql = """
        SELECT [date], wm_yr_wk, weekday, wday, [month], [year], d,
               event_name_1, event_type_1, event_name_2, event_type_2,
               snap_CA, snap_TX, snap_WI
        FROM   raw.calendar
        WHERE  [date] BETWEEN ? AND ?
    """
    params = (start_date.isoformat(), end_date.isoformat())

    with engine_az.connect() as az:
        src_count = pd.read_sql(
            f"SELECT COUNT(*) AS n FROM ({src_sql}) src",
            az, params=params,
        )["n"].iloc[0]
    log.info("  source rows in window: %s", f"{src_count:,}")

    delete_destination_slice(
        conn_sf,
        "DELETE FROM RETAIL_DB.RAW.CALENDAR WHERE date BETWEEN %s AND %s",
        params,
    )

    with engine_az.connect() as az:
        read_iter = pd.read_sql_query(src_sql, az, params=params,
                                      chunksize=CHUNKSIZE)
        written = write_chunks_to_snowflake(read_iter, conn_sf, "CALENDAR")

    verify_parity("calendar", src_count, written)


def extract_sell_prices(engine_az, conn_sf,
                        week_values: list) -> None:
    log.info("=== sell_prices ===")
    if not week_values:
        log.warning("  No fiscal weeks in window -> skipping sell_prices")
        return

    src_ph = in_clause_placeholders(week_values, "?")
    src_sql = f"""
        SELECT store_id, item_id, wm_yr_wk, sell_price
        FROM   raw.sell_prices
        WHERE  wm_yr_wk IN ({src_ph})
    """

    with engine_az.connect() as az:
        src_count = pd.read_sql(
            f"SELECT COUNT(*) AS n FROM ({src_sql}) src",
            az, params=tuple(week_values),
        )["n"].iloc[0]
    log.info("  source rows for %d weeks: %s",
             len(week_values), f"{src_count:,}")

    sf_ph = in_clause_placeholders(week_values, "%s")
    delete_destination_slice(
        conn_sf,
        f"DELETE FROM RETAIL_DB.RAW.SELL_PRICES "
        f"WHERE wm_yr_wk IN ({sf_ph})",
        tuple(week_values),
    )

    with engine_az.connect() as az:
        read_iter = pd.read_sql_query(src_sql, az,
                                      params=tuple(week_values),
                                      chunksize=CHUNKSIZE)
        written = write_chunks_to_snowflake(read_iter, conn_sf, "SELL_PRICES")

    verify_parity("sell_prices", src_count, written)


def extract_sales_train(engine_az, conn_sf,
                        d_values: list) -> None:
    log.info("=== sales_train ===")
    if not d_values:
        log.warning("  No d_X values in window -> skipping sales_train")
        return

    src_ph = in_clause_placeholders(d_values, "?")
    src_sql = f"""
        SELECT id, item_id, dept_id, cat_id, store_id, state_id, d, sales
        FROM   raw.sales_train
        WHERE  d IN ({src_ph})
    """

    with engine_az.connect() as az:
        src_count = pd.read_sql(
            f"SELECT COUNT(*) AS n FROM ({src_sql}) src",
            az, params=tuple(d_values),
        )["n"].iloc[0]
    log.info("  source rows for %d days: %s",
             len(d_values), f"{src_count:,}")

    sf_ph = in_clause_placeholders(d_values, "%s")
    delete_destination_slice(
        conn_sf,
        f"DELETE FROM RETAIL_DB.RAW.SALES_TRAIN "
        f"WHERE d IN ({sf_ph})",
        tuple(d_values),
    )

    with engine_az.connect() as az:
        read_iter = pd.read_sql_query(src_sql, az,
                                      params=tuple(d_values),
                                      chunksize=CHUNKSIZE)
        written = write_chunks_to_snowflake(read_iter, conn_sf, "SALES_TRAIN")

    verify_parity("sales_train", src_count, written)


# -----------------------------------------------------------------------------
# 7. Orchestrator.
# -----------------------------------------------------------------------------
def main() -> int:
    args = parse_args()
    load_and_check_env()

    log.info("=== Azure SQL -> Snowflake extract ===")
    log.info("Window:  %s -> %s (inclusive)",
             args.start_date.isoformat(), args.end_date.isoformat())
    log.info("Tables:  %s", ", ".join(args.tables))
    overall_start = time.time()

    engine_az = connect_azure_sql()
    # Absorb cold-start 40613/40197 here so Airflow's task-level retries=2
    # is a real backstop, not the first line of defence.
    wake_azure_sql(engine_az)
    conn_sf = connect_snowflake()
    try:
        mapping = get_date_mapping(engine_az, args.start_date, args.end_date)
        if mapping.empty:
            log.warning("No calendar rows in window -- nothing to do.")
            return 0

        d_values = mapping["d"].tolist()
        week_values = sorted(mapping["wm_yr_wk"].unique().tolist())

        # Load order = dependency order. Calendar first (smallest -- proves
        # the pipe is open end-to-end before we move millions of rows).
        if "calendar" in args.tables:
            extract_calendar(engine_az, conn_sf,
                             args.start_date, args.end_date)
        if "sell_prices" in args.tables:
            extract_sell_prices(engine_az, conn_sf, week_values)
        if "sales_train" in args.tables:
            extract_sales_train(engine_az, conn_sf, d_values)

    finally:
        try:
            conn_sf.close()
            log.info("Closed Snowflake connection.")
        except Exception as e:  # noqa: BLE001
            log.warning("Snowflake close raised: %s", e)
        try:
            engine_az.dispose()
            log.info("Disposed Azure SQL engine.")
        except Exception as e:  # noqa: BLE001
            log.warning("Azure SQL dispose raised: %s", e)

    elapsed = time.time() - overall_start
    log.info("=== Done. Total elapsed: %.1f min (%.0f sec) ===",
             elapsed / 60, elapsed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
