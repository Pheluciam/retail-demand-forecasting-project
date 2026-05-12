"""
Smoke test: verify pyodbc can talk to Azure SQL Database.

Run from the project root with the venv activated:
    python scripts/smoke_test_azure_sql.py

Reads connection details from .env (which is gitignored).
"""

import os
import pyodbc
from dotenv import load_dotenv

# 1. Load secrets from .env into environment variables
load_dotenv()

# 2. Show which ODBC drivers pyodbc can see (sanity check)
print("=== ODBC drivers visible to pyodbc ===")
for driver in pyodbc.drivers():
    print(f"  {driver}")

# 3. Build the Azure SQL connection string
conn_str = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    f"SERVER={os.getenv('AZURE_SQL_SERVER')};"
    f"DATABASE={os.getenv('AZURE_SQL_DATABASE')};"
    f"UID={os.getenv('AZURE_SQL_USER')};"
    f"PWD={os.getenv('AZURE_SQL_PASSWORD')};"
    "Encrypt=yes;"
    "TrustServerCertificate=no;"
    "Connection Timeout=90;"  # bumped from 30 — covers Free Serverless auto-pause wake
)

# 4. Connect and run one trivial query
print("\n=== Connecting to Azure SQL ===")
print("(If the database has auto-paused, the first connect may take 30-60 seconds...)")
with pyodbc.connect(conn_str) as conn:
    cursor = conn.cursor()
    cursor.execute("SELECT @@VERSION")
    version_row = cursor.fetchone()
    print("Connected successfully.\n")
    print("Server version returned:")
    print(version_row[0])
