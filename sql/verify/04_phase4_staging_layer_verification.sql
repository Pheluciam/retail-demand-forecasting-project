-- =============================================================================
-- 04_phase4_staging_layer_verification.sql
-- =============================================================================
-- Phase 4 session 2 -- independent Snowflake-side verification of the dbt
-- staging layer (RETAIL_DB.STAGING).
--
-- Context:
--   * Phase 4 session 1 scaffolded the dbt project; dbt debug verified.
--   * Phase 4 session 2 built the staging layer:
--       - stg_m5_calendar     (date cast + SNAP rename)
--       - stg_m5_sell_prices  (passthrough minus loaded_at)
--       - stg_m5_sales_train  (CTE pattern + LEFT JOIN to calendar for date)
--   * Final dbt build: PASS=17 (3 views + 14 tests) in 4.5s.
--
-- Purpose:
--   dbt build already ran the 14 model-level tests. This file is the
--   *independent* verification, executed separately in Snowsight, to confirm
--   the staging views look right from Snowflake's perspective: row count
--   parity vs RAW, no unexpected NULLs, date range invariants hold, and the
--   d-NNNN -> sale_date join translation worked at scale (not just on the
--   5 rows we eyeballed during the audit).
--
-- How to run:
--   1. Sign in to Snowsight as PHELUCIAM (RETAIL_ENGINEER role).
--   2. Paste this entire file into a worksheet named
--      04_phase4_staging_layer_verification.
--   3. Run All. Read each section against the Expected block below.
--
-- Expected results:
--
--   Section 1 -- eyeball samples (5 rows each, content sanity check)
--   Section 2 -- RAW vs STAGING row count parity
--       Staging is a view over RAW, so counts should match exactly per table.
--   Section 3 -- NULL sentinel checks
--       Zero NULLs across all key columns; especially sale_date in
--       stg_m5_sales_train (the calendar-join sentinel).
--   Section 4 -- date range invariants
--       MIN(sale_date) = 2011-01-29 (M5 day d_1)
--       MAX(sale_date) >= 2014-01-04 (last DAG-extracted day at handoff;
--                                     future-proof in case more DAGs run)
--   Section 5 -- PASS/FAIL rollup (CTE summary, matches Phase 3 pattern)
--       All checks should report PASS.
-- =============================================================================


-- ----------------------------------------------------------------------------
-- 0. Session context -- run as the dbt role, in the right warehouse/db.
-- ----------------------------------------------------------------------------
USE ROLE      RETAIL_ENGINEER;
USE WAREHOUSE WH_RETAIL;
USE DATABASE  RETAIL_DB;
USE SCHEMA    STAGING;


-- ----------------------------------------------------------------------------
-- 1. Eyeball samples -- 5 rows from each staging view.
-- ----------------------------------------------------------------------------

-- 1a. CALENDAR -- confirm date cast + SNAP rename worked.
SELECT
    calendar_date,
    wm_yr_wk,
    weekday,
    d,
    snap_ca,
    snap_tx,
    snap_wi
FROM STG_M5_CALENDAR
ORDER BY calendar_date
LIMIT 5;


-- 1b. SELL_PRICES -- basic shape check.
SELECT
    store_id,
    item_id,
    wm_yr_wk,
    sell_price
FROM STG_M5_SELL_PRICES
LIMIT 5;


-- 1c. SALES_TRAIN -- confirm d -> sale_date join + units_sold rename.
SELECT
    id,
    item_id,
    store_id,
    d,
    sale_date,
    units_sold
FROM STG_M5_SALES_TRAIN
WHERE sale_date BETWEEN '2014-01-01' AND '2014-01-04'
  AND store_id = 'CA_1'
ORDER BY sale_date, item_id
LIMIT 5;


-- ----------------------------------------------------------------------------
-- 2. Row count parity -- staging view should mirror RAW exactly.
-- ----------------------------------------------------------------------------

SELECT
    'CALENDAR' AS table_name,
    (SELECT COUNT(*) FROM RETAIL_DB.RAW.CALENDAR)             AS raw_rows,
    (SELECT COUNT(*) FROM RETAIL_DB.STAGING.STG_M5_CALENDAR)  AS staging_rows
UNION ALL
SELECT
    'SELL_PRICES',
    (SELECT COUNT(*) FROM RETAIL_DB.RAW.SELL_PRICES),
    (SELECT COUNT(*) FROM RETAIL_DB.STAGING.STG_M5_SELL_PRICES)
UNION ALL
SELECT
    'SALES_TRAIN',
    (SELECT COUNT(*) FROM RETAIL_DB.RAW.SALES_TRAIN),
    (SELECT COUNT(*) FROM RETAIL_DB.STAGING.STG_M5_SALES_TRAIN);


-- ----------------------------------------------------------------------------
-- 3. NULL sentinel checks -- no key column should have NULLs.
-- ----------------------------------------------------------------------------

-- Especially: sale_date in STG_M5_SALES_TRAIN. Any NULL here means the
-- LEFT JOIN to stg_m5_calendar missed a row -- catastrophic data drift.
-- dbt's not_null tests already cover this; below is the independent
-- Snowflake-side confirmation, scanning every row (no sampling).
SELECT
    'calendar.calendar_date'        AS column_checked,
    COUNT_IF(calendar_date IS NULL) AS null_count
FROM STG_M5_CALENDAR
UNION ALL
SELECT 'calendar.d',
    COUNT_IF(d IS NULL)
FROM STG_M5_CALENDAR
UNION ALL
SELECT 'sell_prices.sell_price',
    COUNT_IF(sell_price IS NULL)
FROM STG_M5_SELL_PRICES
UNION ALL
SELECT 'sales_train.sale_date',
    COUNT_IF(sale_date IS NULL)
FROM STG_M5_SALES_TRAIN
UNION ALL
SELECT 'sales_train.units_sold',
    COUNT_IF(units_sold IS NULL)
FROM STG_M5_SALES_TRAIN;


-- ----------------------------------------------------------------------------
-- 4. Date range invariants -- MIN/MAX sale_date matches loaded range.
-- ----------------------------------------------------------------------------

-- M5 day 1 = 2011-01-29 (locked decision in LEARNINGS). MAX is bounded
-- only on the lower side -- future DAG runs may push it higher.
SELECT
    MIN(sale_date)            AS min_sale_date,
    MAX(sale_date)            AS max_sale_date,
    COUNT(DISTINCT sale_date) AS distinct_days_loaded
FROM STG_M5_SALES_TRAIN;


-- ----------------------------------------------------------------------------
-- 5. PASS/FAIL rollup -- CTE summary, matches Phase 3 template.
-- ----------------------------------------------------------------------------

-- Each check returns 0 = PASS; any other number = FAIL.
WITH expected AS (
    SELECT 'calendar parity (RAW vs STAGING)'           AS check_name, 0 AS expected
    UNION ALL SELECT 'sell_prices parity (RAW vs STAGING)',     0
    UNION ALL SELECT 'sales_train parity (RAW vs STAGING)',     0
    UNION ALL SELECT 'calendar.calendar_date NOT NULL',         0
    UNION ALL SELECT 'calendar.d NOT NULL',                     0
    UNION ALL SELECT 'sell_prices.sell_price NOT NULL',         0
    UNION ALL SELECT 'sales_train.sale_date NOT NULL',          0
    UNION ALL SELECT 'sales_train.units_sold NOT NULL',         0
    UNION ALL SELECT 'sales_train MIN(sale_date) = 2011-01-29', 0
    UNION ALL SELECT 'sales_train MAX(sale_date) >= 2014-01-04', 0
),
actual AS (
    SELECT 'calendar parity (RAW vs STAGING)' AS check_name,
        (SELECT COUNT(*) FROM RETAIL_DB.RAW.CALENDAR) -
        (SELECT COUNT(*) FROM RETAIL_DB.STAGING.STG_M5_CALENDAR) AS actual
    UNION ALL
    SELECT 'sell_prices parity (RAW vs STAGING)',
        (SELECT COUNT(*) FROM RETAIL_DB.RAW.SELL_PRICES) -
        (SELECT COUNT(*) FROM RETAIL_DB.STAGING.STG_M5_SELL_PRICES)
    UNION ALL
    SELECT 'sales_train parity (RAW vs STAGING)',
        (SELECT COUNT(*) FROM RETAIL_DB.RAW.SALES_TRAIN) -
        (SELECT COUNT(*) FROM RETAIL_DB.STAGING.STG_M5_SALES_TRAIN)
    UNION ALL
    SELECT 'calendar.calendar_date NOT NULL',
        (SELECT COUNT_IF(calendar_date IS NULL) FROM STG_M5_CALENDAR)
    UNION ALL
    SELECT 'calendar.d NOT NULL',
        (SELECT COUNT_IF(d IS NULL) FROM STG_M5_CALENDAR)
    UNION ALL
    SELECT 'sell_prices.sell_price NOT NULL',
        (SELECT COUNT_IF(sell_price IS NULL) FROM STG_M5_SELL_PRICES)
    UNION ALL
    SELECT 'sales_train.sale_date NOT NULL',
        (SELECT COUNT_IF(sale_date IS NULL) FROM STG_M5_SALES_TRAIN)
    UNION ALL
    SELECT 'sales_train.units_sold NOT NULL',
        (SELECT COUNT_IF(units_sold IS NULL) FROM STG_M5_SALES_TRAIN)
    UNION ALL
    SELECT 'sales_train MIN(sale_date) = 2011-01-29',
        CASE WHEN (SELECT MIN(sale_date) FROM STG_M5_SALES_TRAIN) = '2011-01-29'
             THEN 0 ELSE 1 END
    UNION ALL
    SELECT 'sales_train MAX(sale_date) >= 2014-01-04',
        CASE WHEN (SELECT MAX(sale_date) FROM STG_M5_SALES_TRAIN) >= '2014-01-04'
             THEN 0 ELSE 1 END
)
SELECT
    e.check_name,
    a.actual,
    CASE
        WHEN e.expected = a.actual THEN 'PASS'
        ELSE 'FAIL'
    END AS status
FROM expected e
JOIN actual a
    ON e.check_name = a.check_name
ORDER BY e.check_name;
