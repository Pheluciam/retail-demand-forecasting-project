"""
m5_daily_extract -- the first DAG in the retail-demand-forecasting pipeline.

Wraps scripts/extract_azure_to_snowflake.py as a single Airflow task. Each
scheduled run extracts ONE day's worth of M5 data from Azure SQL into
Snowflake -- the "simulated freshness via date-partitioned extraction"
pattern locked in PROJECT_CONTEXT.md.

DAG anatomy at a glance:
    schedule:          @daily
    start_date:        2014-01-01  (the day after the 3-year backfill ends)
    catchup:           False       (don't auto-backfill 2.5 years on first start)
    retries:           2           (Airflow-level backstop; script-level
                                    retry-on-40613 handles the common case)
    retry_delay:       60s
    max_active_runs:   1           (no parallel runs -- they'd contend on the
                                    same DELETE+INSERT window in Snowflake)

The script-level wake_azure_sql() helper absorbs Azure SQL's cold-start
40613/40197 errors so each Airflow task attempt doesn't get burned just
because the DB took 45s to wake. retries=2 here is a true backstop, for
genuinely-unexpected failures: a network hiccup, a transient pyodbc
disconnect mid-stream, etc.
"""

from __future__ import annotations

import logging
import sys
from datetime import timedelta
from pathlib import Path

import pendulum

from airflow.decorators import dag, task


# -----------------------------------------------------------------------------
# Make the existing extract module importable.
# -----------------------------------------------------------------------------
# docker-compose mounts the project's scripts/ folder at /opt/airflow/scripts
# read-only and we set PYTHONPATH there. The path-insert below is belt-and-
# braces in case PYTHONPATH gets unset by some Airflow internal.

SCRIPTS_DIR = Path("/opt/airflow/scripts")
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))


# -----------------------------------------------------------------------------
# Default args -- applied to every task in the DAG unless overridden.
# -----------------------------------------------------------------------------

DEFAULT_ARGS = {
    "owner": "phil",
    "depends_on_past": False,
    # retries: Airflow-level backstop. Script-level wake_azure_sql() already
    # absorbs the common Azure SQL cold-start case (40613/40197), so what
    # remains for Airflow retries is genuinely unexpected: a network drop
    # mid-stream, a Snowflake transient, a chunk that mis-encodes, etc.
    "retries": 2,
    "retry_delay": timedelta(seconds=60),
    "email_on_failure": False,
    "email_on_retry": False,
}


@dag(
    dag_id="m5_daily_extract",
    description=(
        "Daily incremental extract of one date slice of M5 data from "
        "Azure SQL into Snowflake RAW."
    ),
    # Pendulum DateTime for start_date is Airflow's recommended pattern --
    # explicit timezone, no naive-datetime warnings.
    start_date=pendulum.datetime(2014, 1, 1, tz="Australia/Melbourne"),
    schedule="@daily",
    catchup=False,
    max_active_runs=1,
    default_args=DEFAULT_ARGS,
    tags=["m5", "extract", "phase3"],
)

def m5_daily_extract():

    @task(task_id="extract_one_day")
    def extract_one_day(**context) -> str:
        """Extract a single day's slice of all three M5 tables.

        Airflow's `context["ds"]` is the data-interval start date as a
        YYYY-MM-DD string -- exactly the format extract_azure_to_snowflake.py
        expects via --run-date.

        We adapt to the script's existing CLI surface by setting sys.argv
        then calling main(), instead of refactoring main() to take kwargs.
        Keeps the script unchanged and independently runnable from PowerShell.
        """
        run_date: str = context["ds"]

        # Import inside the task body, not at module top-level. Reason:
        # module-level imports run during DAG parsing on the scheduler,
        # which happens every ~30s. Heavy imports (pandas, snowflake) then
        # block DAG parse cycles. Inside-task imports run only when the
        # task actually executes -- which is the cheap right time.
        import extract_azure_to_snowflake as extractor

        # Mimic the PowerShell CLI invocation:
        #   python extract_azure_to_snowflake.py --run-date {ds}
        original_argv = sys.argv
        sys.argv = [
            "extract_azure_to_snowflake.py",
            "--run-date", run_date,
        ]
        try:
            exit_code = extractor.main()
        finally:
            sys.argv = original_argv

        if exit_code != 0:
            # Surface as an Airflow task failure -- not "task succeeded with
            # weird exit code" which the UI would otherwise green-tick.
            raise RuntimeError(
                f"extract_azure_to_snowflake.main() exited {exit_code} "
                f"for run_date={run_date}"
            )

        return f"extracted run_date={run_date}"

    @task(task_id="verify_one_day")
    def verify_one_day(**context) -> str:
        """Independent Snowflake-side verification of the extract task's work.

        Queries Snowflake directly to confirm the three RAW tables landed
        sensible row counts for run_date. Knows nothing about what
        extract_one_day reported -- if the extract task lied or quietly
        skipped a table, this catches it. Same philosophy as the SQL files
        in sql/verify/, but inside the DAG so the loop closes in Airflow.

        Three checks (all must pass), batched into a single SELECT so we
        do one warehouse round-trip instead of three:
            1. CALENDAR has exactly 1 row for run_date.
            2. SELL_PRICES has > 0 rows for the fiscal week covering run_date.
            3. SALES_TRAIN has > 0 rows for the M5 day-code mapped to run_date.

        Any failure -> RuntimeError -> task failure -> DAG failure -> red
        square in Grid view. Standard Airflow failure semantics.
        """
        run_date: str = context["ds"]
        log = logging.getLogger("airflow.task")
        log.info("verify_one_day starting for run_date=%s", run_date)

        # Reuse the extract module's Snowflake connection helper. Same
        # inside-task import pattern as extract_one_day for the same
        # reason: keep DAG-parse cycles cheap.
        import extract_azure_to_snowflake as extractor

        # Single round-trip: three COUNTs combined as scalar subqueries
        # in one SELECT. Cheaper than three execute() calls on a warm
        # warehouse; also clearer to read than juggling three cursors.
        sql = (
            "SELECT "
            "    (SELECT COUNT(*) FROM CALENDAR "
            "        WHERE date = %s) AS calendar_rows, "
            "    (SELECT COUNT(*) FROM SELL_PRICES sp "
            "        JOIN CALENDAR c ON sp.wm_yr_wk = c.wm_yr_wk "
            "        WHERE c.date = %s) AS sell_prices_rows, "
            "    (SELECT COUNT(*) FROM SALES_TRAIN s "
            "        JOIN CALENDAR c ON s.d = c.d "
            "        WHERE c.date = %s) AS sales_train_rows"
        )

        conn = extractor.connect_snowflake()
        try:
            cur = conn.cursor()
            try:
                cur.execute(sql, (run_date, run_date, run_date))
                calendar_rows, sell_prices_rows, sales_train_rows = cur.fetchone()
            finally:
                cur.close()
        finally:
            conn.close()

        log.info("  CALENDAR    rows for %s: %d (expected 1)",
                 run_date, calendar_rows)
        log.info("  SELL_PRICES rows for %s: %d (expected > 0)",
                 run_date, sell_prices_rows)
        log.info("  SALES_TRAIN rows for %s: %d (expected > 0)",
                 run_date, sales_train_rows)

        failures = []
        if calendar_rows != 1:
            failures.append(
                f"CALENDAR: expected 1 row for {run_date}, got {calendar_rows}"
            )
        if sell_prices_rows <= 0:
            failures.append(
                f"SELL_PRICES: expected > 0 rows for {run_date}, got {sell_prices_rows}"
            )
        if sales_train_rows <= 0:
            failures.append(
                f"SALES_TRAIN: expected > 0 rows for {run_date}, got {sales_train_rows}"
            )

        if failures:
            raise RuntimeError(
                f"verify_one_day failed for run_date={run_date}: "
                + "; ".join(failures)
            )

        return (
            f"verified run_date={run_date} -- "
            f"calendar={calendar_rows}, "
            f"sell_prices={sell_prices_rows}, "
            f"sales_train={sales_train_rows}"
        )

    extract_one_day() >> verify_one_day()


# Instantiate the DAG. Airflow's scheduler discovers it via this assignment
# at module top level.
dag = m5_daily_extract()
