"""
Create raw tables in Azure SQL Database.

Reads sql/ddl/01_create_raw_tables.sql and executes each batch
(batches are separated by `GO` on its own line, the standard T-SQL convention).

Idempotent: the DDL drops any existing tables before recreating them, so this
script is safe to re-run during development if the schema needs to change.

Run from the project root with the venv activated:
    python scripts/create_raw_tables.py
"""

import os
import re
import pyodbc
from pathlib import Path
from dotenv import load_dotenv

# 1. Load secrets from .env and locate the DDL file
load_dotenv()
PROJECT_ROOT = Path(__file__).parent.parent
DDL_FILE = PROJECT_ROOT / "sql" / "ddl" / "01_create_raw_tables.sql"

# 2. Build the Azure SQL connection string
#    autocommit=True is set on the connection itself, not here.
conn_str = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    f"SERVER={os.getenv('AZURE_SQL_SERVER')};"
    f"DATABASE={os.getenv('AZURE_SQL_DATABASE')};"
    f"UID={os.getenv('AZURE_SQL_USER')};"
    f"PWD={os.getenv('AZURE_SQL_PASSWORD')};"
    "Encrypt=yes;"
    "TrustServerCertificate=no;"
    "Connection Timeout=90;"
)

# 3. Read the DDL file and split it into batches on `GO`
#    The regex matches a line that is just GO (case-insensitive, optional whitespace).
print(f"Reading DDL from: {DDL_FILE.relative_to(PROJECT_ROOT)}")
ddl_text = DDL_FILE.read_text(encoding="utf-8")
batches = re.split(r"(?im)^\s*GO\s*$", ddl_text)
batches = [b.strip() for b in batches if b.strip()]
print(f"Found {len(batches)} SQL batch(es) to execute.\n")

# 4. Execute each batch
#    autocommit=True means each DDL statement commits immediately. For DDL
#    that's what we want — CREATE SCHEMA + DROP TABLE + CREATE TABLE don't
#    play nicely inside a single transaction across some SQL Server versions.
print("=== Connecting to Azure SQL ===")
print("(If the database has auto-paused, the first connect may take 30-60 seconds...)")
with pyodbc.connect(conn_str, autocommit=True) as conn:
    cursor = conn.cursor()
    for i, batch in enumerate(batches, start=1):
        # Print a short preview of each batch so progress is visible
        preview = " ".join(batch.split())[:70]
        print(f"  Batch {i}/{len(batches)}: {preview}...")
        cursor.execute(batch)

print("\nAll DDL executed successfully.")
print("Schema and tables now present in Azure SQL:")
print("  raw.calendar")
print("  raw.sell_prices")
print("  raw.sales_train")
