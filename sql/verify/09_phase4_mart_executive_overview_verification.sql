-- =============================================================================
-- 09_phase4_mart_executive_overview_verification.sql
-- =============================================================================
-- Durable verification for mart_executive_overview.
-- Re-runnable from Snowsight any time after `dbt build --select mart_executive_overview`.
-- Each section is an independent SELECT — paste section by section.
--
-- Sections:
--   1. Upstream parity (units + revenue + date count vs fact_daily_sales)
--   2. PK uniqueness on sale_date
--   3. Active counts reconcile on a sample date
--   4. Headline measure sanity (full-mart totals + coverage)
--   5. Five-row eyeball
--   6. Single-row PASS/FAIL rollup
-- =============================================================================


-- ── Section 1 ── Upstream parity ─────────────────────────────────────────────
-- The mart is a pure aggregation of fact_daily_sales. The headline measures
-- in the mart MUST equal the corresponding aggregates from the fact across
-- the same date range. Any divergence is a build bug — wrong GROUP BY,
-- wrong source, partial materialization, etc.

SELECT
    'units' AS measure,
    (SELECT SUM(total_units_sold)     FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW) AS mart_total,
    (SELECT SUM(units_sold)           FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES)    AS fact_total
UNION ALL
SELECT
    'revenue',
    (SELECT SUM(total_revenue_usd)    FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW),
    (SELECT SUM(revenue_amount_usd)   FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES)
UNION ALL
SELECT
    'date_count',
    (SELECT COUNT(DISTINCT sale_date) FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW),
    (SELECT COUNT(DISTINCT sale_date) FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES);


-- ── Section 2 ── PK uniqueness ───────────────────────────────────────────────
-- COUNT(*) should equal COUNT(DISTINCT sale_date). The third column should
-- be 0. dbt's unique test enforces this at build time; this is the Snowsight
-- side re-confirmation and a re-runnable check after any future change.

SELECT
    COUNT(*)                              AS row_count,
    COUNT(DISTINCT sale_date)             AS distinct_dates,
    COUNT(*) - COUNT(DISTINCT sale_date)  AS duplicates
FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW;

-- ── Section 3 ── Active counts reconcile on a sample date ────────────────────
-- active_item_count and active_store_count use CASE-inside-COUNT-DISTINCT.
-- Re-compute the same values from the fact for one sample date and confirm
-- parity. mart_* and fact_* columns should match exactly.
-- Sample date 2013-06-15 — comfortably inside the backfill range, not an edge.

WITH sample_date AS (
    SELECT DATE '2013-06-15' AS d
),
mart_side AS (
    SELECT
        active_item_count   AS mart_active_items,
        active_store_count  AS mart_active_stores
    FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW
    WHERE sale_date = (SELECT d FROM sample_date)
),
fact_side AS (
    SELECT
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN item_id  END) AS fact_active_items,
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN store_id END) AS fact_active_stores
    FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES
    WHERE sale_date = (SELECT d FROM sample_date)
)
SELECT
    mart_active_items,
    fact_active_items,
    mart_active_stores,
    fact_active_stores
FROM mart_side, fact_side;


-- ── Section 4 ── Headline measure sanity ─────────────────────────────────────
-- Full-mart totals + coverage. Expected reference numbers (from Phase 4
-- session 4 fact verification):
--   total_revenue_all_dates ≈ $93,559,341.40
--   earliest_date           = 2011-01-29
--   latest_date             = 2014-03-21
--   row_count               ≈ 1,148 (depends on coverage gaps)

SELECT
    SUM(total_units_sold)   AS total_units_all_dates,
    SUM(total_revenue_usd)  AS total_revenue_all_dates,
    MIN(sale_date)          AS earliest_date,
    MAX(sale_date)          AS latest_date,
    COUNT(*)                AS row_count
FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW;


-- ── Section 5 ── Five-row eyeball ───────────────────────────────────────────
-- Sample five evenly-spaced dates across coverage. Spot-check that measures
-- are positive, plausible, and active_store_count is at or near 10 on every
-- date (M5 has 10 stores; all are active by mid-2011).

SELECT
    sale_date,
    total_units_sold,
    total_revenue_usd,
    active_item_count,
    active_store_count
FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW
WHERE sale_date IN (
    DATE '2011-01-29',
    DATE '2012-01-01',
    DATE '2013-01-01',
    DATE '2013-12-31',
    DATE '2014-01-04'
)
ORDER BY sale_date;


-- ── Section 6 ── Single-row PASS/FAIL rollup ─────────────────────────────────
-- One-row health check. All four columns should read 'PASS'.
--   units_parity      — mart total units = fact total units
--   revenue_parity    — mart total revenue = fact total revenue
--   pk_unique         — no duplicate sale_dates in the mart
--   active_store_max  — max(active_store_count) <= 10 (the M5 store count)

WITH checks AS (
    SELECT
        (SELECT SUM(total_units_sold)        FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW)
        = (SELECT SUM(units_sold)            FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES)
            AS units_parity_pass,

        (SELECT SUM(total_revenue_usd)       FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW)
        = (SELECT SUM(revenue_amount_usd)    FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES)
            AS revenue_parity_pass,

        (SELECT COUNT(*) - COUNT(DISTINCT sale_date)
         FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW) = 0
            AS pk_unique_pass,

        (SELECT MAX(active_store_count)      FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW) <= 10
            AS active_store_max_pass
)
SELECT
    CASE WHEN units_parity_pass     THEN 'PASS' ELSE 'FAIL' END AS units_parity,
    CASE WHEN revenue_parity_pass   THEN 'PASS' ELSE 'FAIL' END AS revenue_parity,
    CASE WHEN pk_unique_pass        THEN 'PASS' ELSE 'FAIL' END AS pk_unique,
    CASE WHEN active_store_max_pass THEN 'PASS' ELSE 'FAIL' END AS active_store_max
FROM checks;
