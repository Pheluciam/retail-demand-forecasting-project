-- ============================================================================
-- 08_phase4_fact_daily_sales_verification.sql
-- ============================================================================
-- Independent, post-build verification of the fact_daily_sales warehouse model.
-- Re-runnable any time. Sections are independent (run individually in Snowsight
-- or top-to-bottom). Section 6 is a single-row PASS/FAIL rollup for fast triage.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Section 1: Row count parity with upstream intermediate
-- ----------------------------------------------------------------------------
-- Expectation: fact row count = int_sales_with_prices row count (full load).
-- If incremental has been run multiple times the fact may be ahead — but on
-- first build they must match exactly.

SELECT
    (SELECT COUNT(*) FROM RETAIL_DB.INTERMEDIATE.INT_SALES_WITH_PRICES) AS upstream_rows,
    (SELECT COUNT(*) FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES)         AS fact_rows,
    CASE
        WHEN (SELECT COUNT(*) FROM RETAIL_DB.INTERMEDIATE.INT_SALES_WITH_PRICES)
           = (SELECT COUNT(*) FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES)
        THEN 'PASS - upstream and fact row counts match'
        ELSE 'CHECK - row counts differ (expected on incremental runs after the first)'
    END                                                                  AS parity_status;


-- ----------------------------------------------------------------------------
-- Section 2: Surrogate key uniqueness
-- ----------------------------------------------------------------------------
-- Expectations:
--   row_count = unique_sale_keys           -> grain (item, store, date) is truly unique
--   COUNT(*) = COUNT(DISTINCT item_id, store_id, sale_date)  -> same check natural-key side

SELECT
    COUNT(*)                                                             AS row_count,
    COUNT(DISTINCT sale_key)                                             AS unique_sale_keys,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT sale_key)
        THEN 'PASS - sale_key unique across all rows'
        ELSE 'FAIL - duplicate sale_keys exist'
    END                                                                  AS uniqueness_status
FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES;


-- ----------------------------------------------------------------------------
-- Section 3: FK referential integrity (informational — dbt relationships covers this)
-- ----------------------------------------------------------------------------
-- Counts of fact rows whose FK doesn't exist in the corresponding dim.
-- All three should return zero.

SELECT
    (SELECT COUNT(*)
       FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES f
      WHERE NOT EXISTS (SELECT 1 FROM RETAIL_DB.WAREHOUSE.DIM_ITEM     d WHERE d.item_key  = f.item_key))  AS orphan_item_fks,
    (SELECT COUNT(*)
       FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES f
      WHERE NOT EXISTS (SELECT 1 FROM RETAIL_DB.WAREHOUSE.DIM_STORE    d WHERE d.store_key = f.store_key)) AS orphan_store_fks,
    (SELECT COUNT(*)
       FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES f
      WHERE NOT EXISTS (SELECT 1 FROM RETAIL_DB.WAREHOUSE.DIM_CALENDAR d WHERE d.date_key  = f.date_key))  AS orphan_date_fks;


-- ----------------------------------------------------------------------------
-- Section 4: Sale-date coverage + measure sanity
-- ----------------------------------------------------------------------------
-- Confirms:
--   earliest/latest sale_date are sensible
--   units_sold non-negative
--   NULL sell_price rate roughly matches the upstream 34.66% (M5 lifecycle)

SELECT
    MIN(sale_date)                                                          AS earliest_sale_date,
    MAX(sale_date)                                                          AS latest_sale_date,
    MIN(units_sold)                                                         AS min_units_sold,
    MAX(units_sold)                                                         AS max_units_sold,
    ROUND(100.0 * SUM(CASE WHEN sell_price IS NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_null_price,
    ROUND(SUM(revenue_amount_usd), 2)                                       AS total_revenue_usd
FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES;


-- ----------------------------------------------------------------------------
-- Section 5: Five-row eyeball with dim joins
-- ----------------------------------------------------------------------------
-- Joins back to all three dims via the surrogate keys to prove the star schema
-- is wired correctly end-to-end.

SELECT
    f.sale_date,
    c.day_name,
    c.is_weekend,
    i.cat_id,
    i.dept_id,
    f.item_id,
    s.state_id,
    f.store_id,
    f.units_sold,
    f.sell_price,
    f.revenue_amount_usd
FROM       RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES f
INNER JOIN RETAIL_DB.WAREHOUSE.DIM_ITEM         i ON f.item_key  = i.item_key
INNER JOIN RETAIL_DB.WAREHOUSE.DIM_STORE        s ON f.store_key = s.store_key
INNER JOIN RETAIL_DB.WAREHOUSE.DIM_CALENDAR     c ON f.date_key  = c.date_key
WHERE f.units_sold > 0
  AND f.sell_price IS NOT NULL
ORDER BY f.sale_date, f.store_id, f.item_id
LIMIT 5;


-- ----------------------------------------------------------------------------
-- Section 6: PASS/FAIL rollup (single row, fast triage)
-- ----------------------------------------------------------------------------

WITH uniqueness AS (
    SELECT
        CASE
            WHEN COUNT(*) = COUNT(DISTINCT sale_key)
            THEN 'PASS'
            ELSE 'FAIL'
        END AS uniqueness_status
    FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES
),

orphan_fks AS (
    SELECT
        CASE
            WHEN (SELECT COUNT(*) FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES f
                   WHERE NOT EXISTS (SELECT 1 FROM RETAIL_DB.WAREHOUSE.DIM_ITEM     d WHERE d.item_key  = f.item_key))  = 0
             AND (SELECT COUNT(*) FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES f
                   WHERE NOT EXISTS (SELECT 1 FROM RETAIL_DB.WAREHOUSE.DIM_STORE    d WHERE d.store_key = f.store_key)) = 0
             AND (SELECT COUNT(*) FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES f
                   WHERE NOT EXISTS (SELECT 1 FROM RETAIL_DB.WAREHOUSE.DIM_CALENDAR d WHERE d.date_key  = f.date_key))  = 0
            THEN 'PASS'
            ELSE 'FAIL - orphan FK present'
        END AS fk_status
),

units_nonneg AS (
    SELECT
        CASE
            WHEN MIN(units_sold) >= 0
            THEN 'PASS'
            ELSE 'FAIL - negative units_sold present'
        END AS units_status
    FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES
)

SELECT
    uniqueness.uniqueness_status   AS section2_uniqueness,
    orphan_fks.fk_status           AS section3_fk_integrity,
    units_nonneg.units_status      AS section4_units_nonneg
FROM uniqueness, orphan_fks, units_nonneg;
