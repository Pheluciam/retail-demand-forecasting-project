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
