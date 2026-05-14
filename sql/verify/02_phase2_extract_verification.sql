-- ============================================================================
-- 02_phase2_extract_verification.sql  (Azure SQL / T-SQL)
-- ============================================================================
-- Source-side row-count verification for Phase 2's Azure SQL -> Snowflake
-- backfill (window: 2011-01-29 -> 2013-12-31, inclusive).
--
-- Each query computes what scripts/extract_azure_to_snowflake.py SHOULD have
-- pulled out of Azure SQL for the 3-year window. Run alongside the
-- Snowflake-side check in sql/snowflake/02_extract_smoke_tests.sql Section 5
-- to prove end-to-end parity:  Azure SQL count  ==  Snowflake count.
--
-- Run in Azure Data Studio, VS Code mssql extension, or the Azure portal
-- Query editor. Connect as sqladmin to sqldb-m5-source.
--
-- Phase: 2 — Snowflake + extraction
-- Created: 2026-05-14 (Phase 2 session 3 — backfill closeout)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Section 1 — Source-side row counts for the 3-year backfill window.
-- ----------------------------------------------------------------------------
-- These mirror the filters the extract script applies at runtime:
--   calendar    -> WHERE [date] BETWEEN start AND end
--   sell_prices -> WHERE wm_yr_wk IN (distinct weeks inside window)
--   sales_train -> WHERE d IN (d codes mapping to dates inside window)
--
-- If these counts match the destination counts in Snowflake (Section 5 of
-- sql/snowflake/02_extract_smoke_tests.sql), backfill parity is proven.

SELECT 'calendar'    AS table_name,
       COUNT_BIG(*)  AS row_count,
       CAST(1068     AS BIGINT) AS expected,
       CASE WHEN COUNT_BIG(*) = 1068     THEN 'OK' ELSE 'MISMATCH' END AS status
FROM   raw.calendar
WHERE  [date] BETWEEN '2011-01-29' AND '2013-12-31'
UNION ALL
SELECT 'sell_prices' AS table_name,
       COUNT_BIG(*)  AS row_count,
       CAST(3040105  AS BIGINT) AS expected,
       CASE WHEN COUNT_BIG(*) = 3040105 THEN 'OK' ELSE 'MISMATCH' END AS status
FROM   raw.sell_prices
WHERE  wm_yr_wk IN (
    SELECT DISTINCT wm_yr_wk
    FROM   raw.calendar
    WHERE  [date] BETWEEN '2011-01-29' AND '2013-12-31'
)
UNION ALL
SELECT 'sales_train' AS table_name,
       COUNT_BIG(*)  AS row_count,
       CAST(32563320 AS BIGINT) AS expected,
       CASE WHEN COUNT_BIG(*) = 32563320 THEN 'OK' ELSE 'MISMATCH' END AS status
FROM   raw.sales_train
WHERE  d IN (
    SELECT d
    FROM   raw.calendar
    WHERE  [date] BETWEEN '2011-01-29' AND '2013-12-31'
)
ORDER BY table_name;

-- Expected output:
--   table_name  | row_count   | expected    | status
--   ------------+-------------+-------------+--------
--   calendar    | 1,068       | 1,068       | OK
--   sales_train | 32,563,320  | 32,563,320  | OK
--   sell_prices | 3,040,105   | 3,040,105   | OK
--
-- Note: COUNT_BIG(*) returns BIGINT. Used defensively even though our counts
-- are well under the 2.1B INT limit -- same habit established in
-- sql/verify/01_phase1_load_verification.sql.


-- ----------------------------------------------------------------------------
-- Section 2 — Spot-check a single date inside the window.
-- ----------------------------------------------------------------------------
-- Useful if Section 1 shows MISMATCH and you want to drill in. Picks a date
-- in the middle of the window (2012-06-15) and confirms the day-level row
-- count for sales_train is exactly 30,490 (one row per item-store series).

SELECT s.d, c.[date], COUNT_BIG(*) AS rows_for_date
FROM   raw.sales_train s
INNER JOIN raw.calendar c ON c.d = s.d
WHERE  c.[date] = '2012-06-15'
GROUP BY s.d, c.[date];

-- Expected:
--   d        | date       | rows_for_date
--   ---------+------------+---------------
--   d_<N>    | 2012-06-15 | 30,490
