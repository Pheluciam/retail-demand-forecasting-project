-- ============================================================================
-- 04_phase4_int_sales_with_prices_verification.sql
-- ============================================================================
-- Independent, post-build verification of the int_sales_with_prices model.
-- Re-runnable any time. Sections are independent (run individually in Snowsight
-- or top-to-bottom). Section 5 is a single-row PASS/FAIL rollup for fast triage.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Section 1: Row-count parity with upstream staging
-- ----------------------------------------------------------------------------
-- Expectation: int row count = stg_m5_sales_train row count.
-- A mismatch means the join either fanned out (multi-match duplicates) or
-- dropped rows (shouldn't be possible with a LEFT JOIN, but trust-but-verify).

SELECT
    (SELECT COUNT(*) FROM RETAIL_DB.INTERMEDIATE.INT_SALES_WITH_PRICES) AS int_row_count,
    (SELECT COUNT(*) FROM RETAIL_DB.STAGING.STG_M5_SALES_TRAIN)         AS stg_row_count,
    CASE
        WHEN (SELECT COUNT(*) FROM RETAIL_DB.INTERMEDIATE.INT_SALES_WITH_PRICES)
           = (SELECT COUNT(*) FROM RETAIL_DB.STAGING.STG_M5_SALES_TRAIN)
        THEN 'PASS - no fan-out, no row drops'
        ELSE 'FAIL - investigate'
    END                                                                  AS parity_status;


-- ----------------------------------------------------------------------------
-- Section 2: NULL-price rate (informational, not pass/fail)
-- ----------------------------------------------------------------------------
-- A meaningful proportion of rows will have no sell_price - M5 lists prices
-- only for actively-stocked products in a given fiscal week. Currently ~35%.

SELECT
    COUNT(*)                                                    AS total_rows,
    COUNT(sell_price)                                           AS rows_with_price,
    COUNT(*) - COUNT(sell_price)                                AS rows_without_price,
    ROUND(100.0 * (COUNT(*) - COUNT(sell_price)) / COUNT(*), 2) AS pct_without_price
FROM RETAIL_DB.INTERMEDIATE.INT_SALES_WITH_PRICES;


-- ----------------------------------------------------------------------------
-- Section 3: Sales-without-price anomaly check (PASS/FAIL)
-- ----------------------------------------------------------------------------
-- Expectation: zero rows where units_sold > 0 AND sell_price IS NULL.
-- If any rows return, that's a real data-quality issue - a sale was recorded
-- for a product/store/week that has no active price. Worth investigating
-- before downstream marts or Power BI consume the data.

SELECT
    COUNT(*)                                                  AS anomaly_rows,
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS - every priceless row has zero units_sold'
        ELSE 'FAIL - ' || COUNT(*) || ' rows have sales but no price'
    END                                                       AS anomaly_status
FROM RETAIL_DB.INTERMEDIATE.INT_SALES_WITH_PRICES
WHERE units_sold > 0
  AND sell_price IS NULL;


-- ----------------------------------------------------------------------------
-- Section 4: 10-row eyeball with revenue math (informational)
-- ----------------------------------------------------------------------------
-- Spot-check that units_sold * sell_price = revenue_amount_usd at the row level.
-- Filtered to rows with a price so the sample isn't all NULLs.

SELECT
    sale_date,
    store_id,
    item_id,
    wm_yr_wk,
    units_sold,
    sell_price,
    revenue_amount_usd
FROM RETAIL_DB.INTERMEDIATE.INT_SALES_WITH_PRICES
WHERE sell_price IS NOT NULL
LIMIT 10;


-- ----------------------------------------------------------------------------
-- Section 5: PASS/FAIL rollup (single row, fast triage)
-- ----------------------------------------------------------------------------
-- Run this section alone after any dbt build. One row, all critical checks
-- summarised. If everything reads PASS, the model is in a known-good state.

WITH parity AS (
    SELECT
        CASE
            WHEN (SELECT COUNT(*) FROM RETAIL_DB.INTERMEDIATE.INT_SALES_WITH_PRICES)
               = (SELECT COUNT(*) FROM RETAIL_DB.STAGING.STG_M5_SALES_TRAIN)
            THEN 'PASS'
            ELSE 'FAIL'
        END AS parity_status
),

anomaly AS (
    SELECT
        CASE
            WHEN COUNT(*) = 0 THEN 'PASS'
            ELSE 'FAIL (' || COUNT(*) || ' rows)'
        END AS anomaly_status
    FROM RETAIL_DB.INTERMEDIATE.INT_SALES_WITH_PRICES
    WHERE units_sold > 0
      AND sell_price IS NULL
)

SELECT
    parity.parity_status   AS section1_parity,
    anomaly.anomaly_status AS section3_anomaly
FROM parity, anomaly;
