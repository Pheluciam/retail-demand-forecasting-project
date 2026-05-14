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

import sys
from datetime import datetime, timedelta
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

    extract_one_day()


# Instantiate the DAG. Airflow's scheduler discovers it via this assignment
# at module top level.
dag = m5_daily_extract()
