-- ============================================================================
-- 01_phase1_load_verification.sql
-- ============================================================================
-- Post-load verification queries for Phase 1 bulk load of M5 data into
-- Azure SQL Database `raw` schema.
--
-- Each section confirms a different aspect of the load:
--   1. Row counts match the math-derived expected values
--   2. Table schemas match what the DDL created
--   3. Sample rows from each table look like sensible content
--
-- Usage:
--   - Copy each section into the Azure portal Query editor and run, OR
--   - Run programmatically via a Python helper (same pattern as
--     scripts/create_raw_tables.py, splitting on `GO` boundaries)
--
-- Created: 2026-05-13 (Phase 1 wrap-up)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Section 1 — Row count summary
-- ----------------------------------------------------------------------------
-- Confirms the bulk load delivered the expected number of rows in each table.
-- Compares actual COUNT(*) to the math-derived expected value and produces a
-- one-glance OK / MISMATCH status column.

SELECT 'calendar'    AS table_name, COUNT_BIG(*) AS row_count, CAST(1969     AS BIGINT) AS expected, CASE WHEN COUNT_BIG(*) = 1969     THEN 'OK' ELSE 'MISMATCH' END AS status FROM raw.calendar
UNION ALL
SELECT 'sell_prices' AS table_name, COUNT_BIG(*) AS row_count, CAST(6841121  AS BIGINT) AS expected, CASE WHEN COUNT_BIG(*) = 6841121  THEN 'OK' ELSE 'MISMATCH' END AS status FROM raw.sell_prices
UNION ALL
SELECT 'sales_train' AS table_name, COUNT_BIG(*) AS row_count, CAST(59181090 AS BIGINT) AS expected, CASE WHEN COUNT_BIG(*) = 59181090 THEN 'OK' ELSE 'MISMATCH' END AS status FROM raw.sales_train
ORDER BY table_name;
-- Expected output:
--   table_name   | row_count   | expected    | status
--   -------------+-------------+-------------+----------
--   calendar     | 1,969       | 1,969       | OK
--   sales_train  | 59,181,090  | 59,181,090  | OK
--   sell_prices  | 6,841,121   | 6,841,121   | OK
--
-- Note: `COUNT_BIG(*)` returns BIGINT (vs `COUNT(*)` which returns INT and
-- can overflow on tables > 2.1B rows). Used pre-emptively as a habit.
--
-- If any row shows MISMATCH: re-run the loader script — it's idempotent
-- (TRUNCATE-then-INSERT) so safe to start over.


-- ----------------------------------------------------------------------------
-- Section 2 — Schema verification
-- ----------------------------------------------------------------------------
-- Confirms the table structures match what the DDL was supposed to create.
-- Useful for catching schema drift (columns manually added/dropped/renamed
-- outside the DDL script).

SELECT
    TABLE_NAME,
    COUNT(*) AS column_count
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'raw'
GROUP BY TABLE_NAME
ORDER BY TABLE_NAME;
-- Expected output:
--   TABLE_NAME   | column_count
--   -------------+-------------
--   calendar     | 14
--   sales_train  | 8
--   sell_prices  | 4
--
-- If any count differs: schema has drifted from `sql/ddl/01_create_raw_tables.sql`.
-- Diagnose with: SELECT * FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='raw'
-- ORDER BY TABLE_NAME, ORDINAL_POSITION;


-- ----------------------------------------------------------------------------
-- Section 3 — Eyeball calendar
-- ----------------------------------------------------------------------------
-- Smallest table — easy to look at every column. Confirms the calendar columns
-- look like calendar data (real dates, real weekday names, event flags, SNAP
-- flags as 0/1, mostly NULL event_* columns).

SELECT TOP 5 *
FROM raw.calendar
ORDER BY date;
-- Expected:
--   - date values starting at '2011-01-29' (M5 start date)
--   - weekday: 'Saturday', 'Sunday', 'Monday', 'Tuesday', 'Wednesday' (in order)
--   - wm_yr_wk: 11101 for first ~6 rows (WMart fiscal week)
--   - d: 'd_1', 'd_2', 'd_3', 'd_4', 'd_5' (one-to-one with date)
--   - snap_CA / snap_TX / snap_WI: 0 or 1
--   - event_name_1 / event_type_1: mostly NULL (most days have no event)


-- ----------------------------------------------------------------------------
-- Section 4 — Eyeball sell_prices
-- ----------------------------------------------------------------------------
-- Confirms prices look like prices: positive values, reasonable cents precision,
-- recognisable id formats.

SELECT TOP 5 *
FROM raw.sell_prices
ORDER BY store_id, item_id, wm_yr_wk;
-- Expected:
--   - store_id: 'CA_1' (alphabetically first)
--   - item_id: starting 'FOODS_1_001' or 'HOBBIES_1_001'
--   - wm_yr_wk: 11101+ (WMart fiscal week)
--   - sell_price: positive values, typically $0.50 - $20.00 range
--   - DECIMAL precision visible (e.g. 9.5800 not 9.58)


-- ----------------------------------------------------------------------------
-- Section 5 — Eyeball sales_train
-- ----------------------------------------------------------------------------
-- Confirms the wide-to-long unpivot produced sensible long-format rows.
-- Filter on `sales > 0` because retail demand is sparse — most (item, day)
-- combinations have 0 sales, so a plain TOP 5 would just show zero rows.

SELECT TOP 5 *
FROM raw.sales_train
WHERE sales > 0
ORDER BY id, d;
-- Expected:
--   - id: ends in '_evaluation' (since we loaded sales_train_evaluation.csv)
--   - item_id / dept_id / cat_id / store_id / state_id: matching the id prefix
--   - d: 'd_<n>' format (matches calendar.d for joining)
--   - sales: small positive integers (typically 1-20 units)
