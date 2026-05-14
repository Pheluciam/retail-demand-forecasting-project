-- =============================================================================
-- 03_phase3_dag_extract_verification.sql
-- =============================================================================
-- Phase 3 session 1 -- independent Snowflake-side verification of the first
-- two Airflow-orchestrated daily incremental extracts.
--
-- Context:
--   * Phase 2 backfill loaded 2011-01-29 through 2013-12-31 (one-shot
--     PowerShell command, 35.6M rows in 27.3 min).
--   * Phase 3 session 1 introduced the Airflow stack (Docker Compose,
--     LocalExecutor) and the first DAG (m5_daily_extract).
--   * The DAG was triggered manually for two consecutive days via the
--     Airflow CLI inside the scheduler container:
--         docker compose exec airflow-scheduler airflow dags trigger \
--             m5_daily_extract -e 2014-01-01T00:00:00
--         docker compose exec airflow-scheduler airflow dags trigger \
--             m5_daily_extract -e 2014-01-02T00:00:00
--
-- Purpose:
--   The script (scripts/extract_azure_to_snowflake.py) already performs its
--   own pre-flight + post-action parity check inside each run. This file is
--   the *independent* verification -- run separately from Snowsight, after
--   the DAG runs complete, to confirm the data actually landed in the
--   expected shape from a Snowflake perspective.
--
-- How to run:
--   1. Sign in to Snowsight as PHELUCIAM (RETAIL_ENGINEER role).
--   2. Paste this entire file into a new worksheet.
--   3. Run All. Inspect each section's results against the Expected block
--      below.
--
-- Expected results (after both DAG runs land cleanly):
--
--   Section 1 -- calendar
--     run_date    | calendar_rows
--     ------------+--------------
--     2014-01-01  | 1
--     2014-01-02  | 1
--
--   Section 2 -- sell_prices (weekly granularity)
--     run_date    | wm_yr_wk | sell_prices_rows
--     ------------+----------+-----------------
--     2014-01-01  | 11448    | 25939
--     2014-01-02  | 11448    | 25939
--     (Both dates fall in the same fiscal week, so the same 25,939 rows
--      satisfy both. This is correct, not a duplicate.)
--
--   Section 3 -- sales_train (daily granularity)
--     run_date    | d      | sales_train_rows
--     ------------+--------+-----------------
--     2014-01-01  | d_339  | 30490
--     2014-01-02  | d_340  | 30490
--
--   Section 4 -- audit columns
--     All loaded_at timestamps should fall on 2026-05-14, the Phase 3
--     session 1 date. Confirms these rows arrived via the Airflow run,
--     not via some other route.
--
--   Section 5 -- PASS / FAIL summary (single result set)
--     One row per individual check (6 total: 2 dates x 3 tables) with a
--     status column. Six PASS rows = full success. Read THIS section if you
--     just want the at-a-glance "did everything land?" answer. Sections 1-4
--     are the detailed views for debugging when something fails.
-- =============================================================================

USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE WH_RETAIL;
USE DATABASE RETAIL_DB;
USE SCHEMA RAW;


-- -----------------------------------------------------------------------------
-- Section 1 -- calendar row counts for the two DAG-extract dates.
-- -----------------------------------------------------------------------------
SELECT
    date AS run_date,
    COUNT(*) AS calendar_rows
FROM CALENDAR
WHERE date IN ('2014-01-01', '2014-01-02')
GROUP BY date
ORDER BY date;


-- -----------------------------------------------------------------------------
-- Section 2 -- sell_prices row counts for the fiscal week(s) covering the
-- two extract dates.
-- -----------------------------------------------------------------------------
-- sell_prices is weekly-grained (one row per item-store-week), so the count
-- is per fiscal week (wm_yr_wk), not per calendar day. We join through
-- calendar to discover which fiscal week each date belongs to.
SELECT
    c.date AS run_date,
    c.wm_yr_wk,
    COUNT(*) AS sell_prices_rows
FROM SELL_PRICES sp
JOIN CALENDAR c
    ON sp.wm_yr_wk = c.wm_yr_wk
WHERE c.date IN ('2014-01-01', '2014-01-02')
GROUP BY c.date, c.wm_yr_wk
ORDER BY c.date;


-- -----------------------------------------------------------------------------
-- Section 3 -- sales_train row counts for the two extract dates.
-- -----------------------------------------------------------------------------
-- sales_train is daily-grained; each date maps to one M5 d-code via the
-- calendar table (e.g. 2014-01-01 -> d_339).
SELECT
    c.date AS run_date,
    c.d,
    COUNT(*) AS sales_train_rows
FROM SALES_TRAIN s
JOIN CALENDAR c
    ON s.d = c.d
WHERE c.date IN ('2014-01-01', '2014-01-02')
GROUP BY c.date, c.d
ORDER BY c.date;


-- -----------------------------------------------------------------------------
-- Section 4 -- loaded_at audit columns, proving the rows arrived via the
-- Airflow-orchestrated runs on 2026-05-14 (not via the Phase 2 backfill or
-- a manual one-off).
-- -----------------------------------------------------------------------------
SELECT
    'sales_train' AS table_name,
    MIN(s.loaded_at) AS first_landed,
    MAX(s.loaded_at) AS last_landed,
    COUNT(*) AS rows_landed
FROM SALES_TRAIN s
JOIN CALENDAR c
    ON s.d = c.d
WHERE c.date IN ('2014-01-01', '2014-01-02');


-- -----------------------------------------------------------------------------
-- Section 5 -- PASS / FAIL summary: one row per individual check.
-- -----------------------------------------------------------------------------
-- Pattern: CTE 'expected' lists what each check should return. CTE 'actual'
-- runs the actual counts. Final SELECT joins them, computes PASS/FAIL.
-- Six checks total: 2 extract dates x 3 raw tables.
-- All 'PASS' = pipeline ran end-to-end correctly for both dates.
WITH expected AS (
    SELECT 'calendar 2014-01-01'    AS check_name, 1     AS expected_rows UNION ALL
    SELECT 'calendar 2014-01-02'    AS check_name, 1     AS expected_rows UNION ALL
    SELECT 'sell_prices 2014-01-01' AS check_name, 25939 AS expected_rows UNION ALL
    SELECT 'sell_prices 2014-01-02' AS check_name, 25939 AS expected_rows UNION ALL
    SELECT 'sales_train 2014-01-01' AS check_name, 30490 AS expected_rows UNION ALL
    SELECT 'sales_train 2014-01-02' AS check_name, 30490 AS expected_rows
),
actual AS (
    SELECT 'calendar 2014-01-01' AS check_name,
        (SELECT COUNT(*) FROM CALENDAR WHERE date = '2014-01-01') AS actual_rows
    UNION ALL
    SELECT 'calendar 2014-01-02',
        (SELECT COUNT(*) FROM CALENDAR WHERE date = '2014-01-02')
    UNION ALL
    SELECT 'sell_prices 2014-01-01',
        (SELECT COUNT(*) FROM SELL_PRICES sp JOIN CALENDAR c ON sp.wm_yr_wk = c.wm_yr_wk WHERE c.date = '2014-01-01')
    UNION ALL
    SELECT 'sell_prices 2014-01-02',
        (SELECT COUNT(*) FROM SELL_PRICES sp JOIN CALENDAR c ON sp.wm_yr_wk = c.wm_yr_wk WHERE c.date = '2014-01-02')
    UNION ALL
    SELECT 'sales_train 2014-01-01',
        (SELECT COUNT(*) FROM SALES_TRAIN s JOIN CALENDAR c ON s.d = c.d WHERE c.date = '2014-01-01')
    UNION ALL
    SELECT 'sales_train 2014-01-02',
        (SELECT COUNT(*) FROM SALES_TRAIN s JOIN CALENDAR c ON s.d = c.d WHERE c.date = '2014-01-02')
)
SELECT
    e.check_name,
    e.expected_rows,
    a.actual_rows,
    CASE
        WHEN e.expected_rows = a.actual_rows THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM expected e
JOIN actual a
    ON e.check_name = a.check_name
ORDER BY e.check_name;
