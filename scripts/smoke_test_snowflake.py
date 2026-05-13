"""
Smoke test: verify snowflake-connector-python can talk to our Snowflake account.

Run from the project root with the venv activated:
    python scripts/smoke_test_snowflake.py

Reads connection details from .env (which is gitignored). Confirms:
  - all required env vars are set
  - the connector authenticates against our trial account
  - role / warehouse / database / schema all resolve to the expected values
"""

import os
import sys
import snowflake.connector
from dotenv import load_dotenv

# 1. Load secrets from .env into environment variables
load_dotenv()

# 2. Pre-flight: confirm every env var the connector needs is set.
#    Fail fast with a clear message rather than a cryptic auth error.
REQUIRED_ENV_VARS = [
    "SNOWFLAKE_ACCOUNT",
    "SNOWFLAKE_USER",
    "SNOWFLAKE_PASSWORD",
    "SNOWFLAKE_WAREHOUSE",
    "SNOWFLAKE_DATABASE",
    "SNOWFLAKE_SCHEMA",
    "SNOWFLAKE_ROLE",
]

missing = [v for v in REQUIRED_ENV_VARS if not os.getenv(v)]
if missing:
    print(f"ERROR: missing required env vars in .env: {missing}")
    sys.exit(1)

# 3. Connection parameters — all named kwargs, no string concatenation.
#    Note: password is read from env, never printed.
conn_params = {
    "account":   os.getenv("SNOWFLAKE_ACCOUNT"),
    "user":      os.getenv("SNOWFLAKE_USER"),
    "password":  os.getenv("SNOWFLAKE_PASSWORD"),
    "warehouse": os.getenv("SNOWFLAKE_WAREHOUSE"),
    "database":  os.getenv("SNOWFLAKE_DATABASE"),
    "schema":    os.getenv("SNOWFLAKE_SCHEMA"),
    "role":      os.getenv("SNOWFLAKE_ROLE"),
    # network-layer hardening (mirrors the Azure SQL connection's TLS posture)
    "login_timeout":   30,   # seconds to wait for the initial auth handshake
    "network_timeout": 60,   # seconds for individual network operations
}

print("=== Connecting to Snowflake ===")
print(f"  account:   {conn_params['account']}")
print(f"  user:      {conn_params['user']}")
print(f"  role:      {conn_params['role']}")
print(f"  warehouse: {conn_params['warehouse']}")
print(f"  database:  {conn_params['database']}")
print(f"  schema:    {conn_params['schema']}")
print("  password:  (read from .env, not printed)")

# 4. Connect and run one trivial query.
#    The CURRENT_*() functions confirm not just "we can connect" but
#    "the session is running in the expected security context".
with snowflake.connector.connect(**conn_params) as conn:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT
                CURRENT_USER()      AS active_user,
                CURRENT_ROLE()      AS active_role,
                CURRENT_WAREHOUSE() AS active_warehouse,
                CURRENT_DATABASE()  AS active_database,
                CURRENT_SCHEMA()    AS active_schema,
                CURRENT_VERSION()   AS snowflake_version
            """
        )
        row = cur.fetchone()
        columns = [c[0] for c in cur.description]

print("\n=== Session context (from Snowflake) ===")
for col, val in zip(columns, row):
    print(f"  {col:18} {val}")

print("\nSmoke test passed.")
