-- ============================================================================
-- 02_extract_smoke_tests.sql  (Snowflake)
-- ============================================================================
-- Reusable smoke-test queries for verifying scripts/extract_azure_to_snowflake.py
-- has landed the right data in Snowflake.
--
-- Run after any extract job (incremental or backfill) to spot-check:
--   - row counts per table
--   - that a specific date is present and looks correct
--   - when the most recent extract ran (via the loaded_at audit column)
--
-- Not destructive. Safe to run any time.
--
-- Run as RETAIL_ENGINEER, warehouse WH_RETAIL.
-- Phase: 2 — Snowflake + extraction
-- First used: 2026-05-13, Phase 2 session 2 smoke-test sign-off.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. Session context.
-- ----------------------------------------------------------------------------

USE ROLE      RETAIL_ENGINEER;
USE WAREHOUSE WH_RETAIL;
USE DATABASE  RETAIL_DB;
USE SCHEMA    RAW;


-- ----------------------------------------------------------------------------
-- 1. Headline row counts — how much data sits in each RAW table right now?
-- ----------------------------------------------------------------------------

SELECT COUNT(*) AS calendar_rows    FROM RETAIL_DB.RAW.CALENDAR;
SELECT COUNT(*) AS sell_prices_rows FROM RETAIL_DB.RAW.SELL_PRICES;
SELECT COUNT(*) AS sales_train_rows FROM RETAIL_DB.RAW.SALES_TRAIN;


-- ----------------------------------------------------------------------------
-- 2. Spot-check a single date — does it look like real Walmart data?
-- ----------------------------------------------------------------------------
-- 2014-03-15 is the canonical smoke-test date used in PROJECT_CONTEXT.
-- A Saturday in California (SNAP_CA=0, SNAP_TX/WI=1). Change the literal to
-- inspect any other date.

SELECT *
FROM   RETAIL_DB.RAW.CALENDAR
WHERE  date = '2014-03-15';


-- ----------------------------------------------------------------------------
-- 3. Freshness — when did the most recent extract run land rows?
-- ----------------------------------------------------------------------------
-- The `loaded_at` audit column is stamped by Snowflake on insert
-- (DEFAULT CURRENT_TIMESTAMP). Useful in Phase 3 for "did the Airflow run
-- happen today?" health checks.

SELECT 'calendar'    AS table_name, MAX(loaded_at) AS latest_load FROM RETAIL_DB.RAW.CALENDAR
UNION ALL
SELECT 'sell_prices' AS table_name, MAX(loaded_at) AS latest_load FROM RETAIL_DB.RAW.SELL_PRICES
UNION ALL
SELECT 'sales_train' AS table_name, MAX(loaded_at) AS latest_load FROM RETAIL_DB.RAW.SALES_TRAIN
ORDER BY table_name;


-- ----------------------------------------------------------------------------
-- 4. Distribution check — rows per date in sales_train.
-- ----------------------------------------------------------------------------
-- Useful for spotting missing dates after a backfill. Each present `d`
-- should have ~30,490 rows (one per item × store series).
-- Joins through calendar to express the result as a real DATE column
-- rather than the raw d_X codes.

SELECT
    c.date                            AS sale_date,
    s.d                               AS d_code,
    COUNT(*)                          AS rows_for_date,
    CASE WHEN COUNT(*) = 30490 THEN 'OK' ELSE 'SHORT' END
                                      AS status
FROM       RETAIL_DB.RAW.SALES_TRAIN  s
INNER JOIN RETAIL_DB.RAW.CALENDAR     c ON c.d = s.d
GROUP BY   c.date, s.d
ORDER BY   c.date;


-- ----------------------------------------------------------------------------
-- 5. Backfill verification — 3-year load (2011-01-29 -> 2013-12-31).
-- ----------------------------------------------------------------------------
-- Run ONCE after the 3-year backfill completes
-- (`extract_azure_to_snowflake.py --start-date 2011-01-29 --end-date 2013-12-31`).
-- Counts the rows that should have landed in each RAW table for this specific
-- window and compares to math-derived expected values.
--
-- Expected math:
--   calendar:    1,068 rows       (337 days in 2011 + 366 in 2012 + 365 in 2013)
--   sell_prices: 3,040,105 rows   (153 fiscal weeks × ~20k item-store rows, observed at runtime)
--   sales_train: 32,563,320 rows  (1,068 days × 30,490 series)
--
-- Why filter by window rather than COUNT(*) unfiltered:
--   Snowflake RAW also contains session-2 smoke-test rows for dates OUTSIDE the
--   backfill window (e.g., 2014-03-15). Filtering by window gives apples-to-apples
--   parity with the Azure SQL source-side check in
--   sql/verify/02_phase2_extract_verification.sql.

SELECT 'calendar'    AS table_name,
       COUNT(*)      AS actual_rows,
       1068          AS expected_rows,
       CASE WHEN COUNT(*) = 1068     THEN 'OK' ELSE 'MISMATCH' END AS status
FROM   RETAIL_DB.RAW.CALENDAR
WHERE  date BETWEEN '2011-01-29' AND '2013-12-31'
UNION ALL
SELECT 'sell_prices' AS table_name,
       COUNT(*)      AS actual_rows,
       3040105       AS expected_rows,
       CASE WHEN COUNT(*) = 3040105 THEN 'OK' ELSE 'MISMATCH' END AS status
FROM   RETAIL_DB.RAW.SELL_PRICES
WHERE  wm_yr_wk IN (
    SELECT DISTINCT wm_yr_wk
    FROM   RETAIL_DB.RAW.CALENDAR
    WHERE  date BETWEEN '2011-01-29' AND '2013-12-31'
)
UNION ALL
SELECT 'sales_train' AS table_name,
       COUNT(*)      AS actual_rows,
       32563320      AS expected_rows,
       CASE WHEN COUNT(*) = 32563320 THEN 'OK' ELSE 'MISMATCH' END AS status
FROM   RETAIL_DB.RAW.SALES_TRAIN
WHERE  d IN (
    SELECT d
    FROM   RETAIL_DB.RAW.CALENDAR
    WHERE  date BETWEEN '2011-01-29' AND '2013-12-31'
)
ORDER BY table_name;

-- Expected output:
--   table_name  | actual_rows | expected_rows | status
--   ------------+-------------+---------------+--------
--   calendar    | 1,068       | 1,068         | OK
--   sales_train | 32,563,320  | 32,563,320    | OK
--   sell_prices | 3,040,105   | 3,040,105     | OK
--
-- If any row shows MISMATCH:
--   1. Run sql/verify/02_phase2_extract_verification.sql against Azure SQL.
--   2. If source counts also differ from expected -> investigate the filter logic.
--   3. If source matches expected but Snowflake doesn't -> re-run the backfill;
--      the extract script is idempotent (DELETE-then-INSERT per window).
