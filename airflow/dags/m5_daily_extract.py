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

from cosmos.airflow.task_group import DbtTaskGroup
from cosmos.config import ExecutionConfig, ProfileConfig, ProjectConfig


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


# -----------------------------------------------------------------------------
# Cosmos config -- see DBT_PIPELINE.md "Airflow orchestration" for the
# full walkthrough.
# -----------------------------------------------------------------------------
# Paths inside the worker container. DBT_PROJECT_PATH is the read-only mount
# declared in docker-compose.yml; DBT_EXECUTABLE_PATH is the isolated venv
# built in the Dockerfile.
DBT_PROJECT_PATH = "/opt/airflow/dbt"
DBT_EXECUTABLE_PATH = "/opt/airflow/dbt_venv/bin/dbt"

# ProfileConfig points Cosmos at the existing profiles.yml (rather than
# translating to an Airflow Connection) -- same env_var() resolution path
# that runs when invoking dbt manually from PowerShell, so both execution
# environments share one credential surface.
project_config = ProjectConfig(DBT_PROJECT_PATH)
profile_config = ProfileConfig(
    profile_name="retail_demand_forecasting",
    target_name="dev",
    profiles_yml_filepath=f"{DBT_PROJECT_PATH}/profiles.yml",
)
execution_config = ExecutionConfig(
    dbt_executable_path=DBT_EXECUTABLE_PATH,
)


@dag(
    dag_id="m5_daily_extract",
    description=(
        "Daily M5 pipeline: extract one date slice from Azure SQL to "
        "Snowflake RAW, verify the extract, run dbt to refresh "
        "STAGING / INTERMEDIATE / WAREHOUSE / MARTS via Cosmos, verify the "
        "dbt build."
    ),
    # Pendulum DateTime for start_date is Airflow's recommended pattern --
    # explicit timezone, no naive-datetime warnings.
    start_date=pendulum.datetime(2014, 1, 1, tz="Australia/Melbourne"),
    schedule="@daily",
    catchup=False,
    max_active_runs=1,
    default_args=DEFAULT_ARGS,
    tags=["m5", "extract", "dbt", "cosmos"],
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
                row = cur.fetchone()
                if row is None:
                    raise RuntimeError(
                        f"verify_one_day: query returned no rows for run_date={run_date}"
                    )
                calendar_rows, sell_prices_rows, sales_train_rows = row
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

    @task(task_id="verify_dbt_one_day")
    def verify_dbt_one_day(**context) -> str:
        """Independent Snowflake-side verification of the dbt task group's work.

        Queries downstream tables across STAGING / INTERMEDIATE / WAREHOUSE /
        MARTS to confirm rows landed for run_date at every layer. Knows nothing
        about what the dbt_models task group reported -- if a dbt model returned
        success but the data didn't actually flow (stale build, partial update,
        table truncated by a prior failed run, etc.), this catches it. Same
        philosophy as verify_one_day, but for the dbt pipeline rather than the
        extract.

        Nine checks batched into a single SELECT for one warehouse round-trip:
            STAGING:      stg_m5_calendar (==1), stg_m5_sell_prices (>0),
                          stg_m5_sales_train (>0)
            INTERMEDIATE: int_sales_with_prices (>0)
            WAREHOUSE:    dim_calendar (>0), dim_item (>0), dim_store (>0),
                          fact_daily_sales (>0 for run_date)
            MARTS:        mart_executive_overview (==1 for run_date)

        Any failure -> RuntimeError -> task failure -> red square in Grid view.
        """
        run_date: str = context["ds"]
        log = logging.getLogger("airflow.task")
        log.info("verify_dbt_one_day starting for run_date=%s", run_date)

        import extract_azure_to_snowflake as extractor

        # Six positional %s binds for the six date-filtered checks; the three
        # dim full-table counts don't take a parameter.
        sql = (
            "SELECT "
            "    (SELECT COUNT(*) FROM STAGING.STG_M5_CALENDAR "
            "        WHERE calendar_date = %s) AS stg_cal_rows, "
            "    (SELECT COUNT(*) FROM STAGING.STG_M5_SELL_PRICES sp "
            "        JOIN STAGING.STG_M5_CALENDAR c ON sp.wm_yr_wk = c.wm_yr_wk "
            "        WHERE c.calendar_date = %s) AS stg_sp_rows, "
            "    (SELECT COUNT(*) FROM STAGING.STG_M5_SALES_TRAIN "
            "        WHERE sale_date = %s) AS stg_sales_rows, "
            "    (SELECT COUNT(*) FROM INTERMEDIATE.INT_SALES_WITH_PRICES "
            "        WHERE sale_date = %s) AS int_rows, "
            "    (SELECT COUNT(*) FROM WAREHOUSE.DIM_CALENDAR) AS dim_cal_rows, "
            "    (SELECT COUNT(*) FROM WAREHOUSE.DIM_ITEM) AS dim_item_rows, "
            "    (SELECT COUNT(*) FROM WAREHOUSE.DIM_STORE) AS dim_store_rows, "
            "    (SELECT COUNT(*) FROM WAREHOUSE.FACT_DAILY_SALES "
            "        WHERE sale_date = %s) AS fact_rows, "
            "    (SELECT COUNT(*) FROM MARTS.MART_EXECUTIVE_OVERVIEW "
            "        WHERE sale_date = %s) AS mart_rows"
        )

        conn = extractor.connect_snowflake()
        try:
            cur = conn.cursor()
            try:
                cur.execute(sql, (run_date, run_date, run_date, run_date,
                                  run_date, run_date))
                row = cur.fetchone()
                if row is None:
                    raise RuntimeError(
                        f"verify_dbt_one_day: query returned no rows "
                        f"for run_date={run_date}"
                    )
                (stg_cal, stg_sp, stg_sales, int_rows,
                 dim_cal, dim_item, dim_store, fact_rows, mart_rows) = row
            finally:
                cur.close()
        finally:
            conn.close()

        log.info("  STAGING.STG_M5_CALENDAR rows for %s: %d (expected 1)",
                 run_date, stg_cal)
        log.info("  STAGING.STG_M5_SELL_PRICES rows for %s: %d (expected > 0)",
                 run_date, stg_sp)
        log.info("  STAGING.STG_M5_SALES_TRAIN rows for %s: %d (expected > 0)",
                 run_date, stg_sales)
        log.info("  INTERMEDIATE.INT_SALES_WITH_PRICES rows for %s: %d (expected > 0)",
                 run_date, int_rows)
        log.info("  WAREHOUSE.DIM_CALENDAR rows: %d (expected > 0)", dim_cal)
        log.info("  WAREHOUSE.DIM_ITEM rows: %d (expected > 0)", dim_item)
        log.info("  WAREHOUSE.DIM_STORE rows: %d (expected > 0)", dim_store)
        log.info("  WAREHOUSE.FACT_DAILY_SALES rows for %s: %d (expected > 0)",
                 run_date, fact_rows)
        log.info("  MARTS.MART_EXECUTIVE_OVERVIEW rows for %s: %d (expected 1)",
                 run_date, mart_rows)

        failures = []
        if stg_cal != 1:
            failures.append(
                f"STAGING.STG_M5_CALENDAR: expected 1 row for {run_date}, got {stg_cal}"
            )
        if stg_sp <= 0:
            failures.append(
                f"STAGING.STG_M5_SELL_PRICES: expected > 0 rows for {run_date}, got {stg_sp}"
            )
        if stg_sales <= 0:
            failures.append(
                f"STAGING.STG_M5_SALES_TRAIN: expected > 0 rows for {run_date}, got {stg_sales}"
            )
        if int_rows <= 0:
            failures.append(
                f"INTERMEDIATE.INT_SALES_WITH_PRICES: expected > 0 rows for {run_date}, got {int_rows}"
            )
        if dim_cal <= 0:
            failures.append(f"WAREHOUSE.DIM_CALENDAR: expected > 0 rows, got {dim_cal}")
        if dim_item <= 0:
            failures.append(f"WAREHOUSE.DIM_ITEM: expected > 0 rows, got {dim_item}")
        if dim_store <= 0:
            failures.append(f"WAREHOUSE.DIM_STORE: expected > 0 rows, got {dim_store}")
        if fact_rows <= 0:
            failures.append(
                f"WAREHOUSE.FACT_DAILY_SALES: expected > 0 rows for {run_date}, got {fact_rows}"
            )
        if mart_rows != 1:
            failures.append(
                f"MARTS.MART_EXECUTIVE_OVERVIEW: expected 1 row for {run_date}, got {mart_rows}"
            )

        if failures:
            raise RuntimeError(
                f"verify_dbt_one_day failed for run_date={run_date}: "
                + "; ".join(failures)
            )

        return (
            f"verified dbt build for {run_date} -- "
            f"stg(cal={stg_cal}, sp={stg_sp}, sales={stg_sales}), "
            f"int={int_rows}, "
            f"dim(cal={dim_cal}, item={dim_item}, store={dim_store}), "
            f"fact={fact_rows}, mart={mart_rows}"
        )

    # Cosmos generates one Airflow task per dbt model + one per dbt test,
    # with dependencies mirrored from dbt's ref() graph. default_args here
    # overrides the DAG-level retries for tasks inside this group; kept at 2
    # to match the rest of the DAG. verify_dbt_one_day (defined above) wires
    # downstream of this group as the final gate.
    dbt_models = DbtTaskGroup(
        group_id="dbt_models",
        project_config=project_config,
        profile_config=profile_config,
        execution_config=execution_config,
        default_args={"retries": 2},
    )

    extract_one_day() >> verify_one_day() >> dbt_models >> verify_dbt_one_day()


# Instantiate the DAG. Airflow's scheduler discovers it via this assignment
# at module top level.
dag = m5_daily_extract()
