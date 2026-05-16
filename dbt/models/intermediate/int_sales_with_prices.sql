-- int_sales_with_prices.sql
-- Joins daily sales to weekly prices and computes revenue.
-- Grain: one row per (store_id, item_id, sale_date).
-- LEFT JOIN to prices preserves sales rows that have no matching price;
-- revenue_amount_usd is NULL in that case ("price unknown", not "zero revenue").
-- See DBT_PIPELINE.md for the full walkthrough.

WITH sales AS (
    SELECT * FROM {{ ref('stg_m5_sales_train') }}
),

prices AS (
    SELECT * FROM {{ ref('stg_m5_sell_prices') }}
),

calendar AS (
    SELECT
        d,
        wm_yr_wk
    FROM {{ ref('stg_m5_calendar') }}
),

sales_with_week AS (
    SELECT
        sales.*,
        calendar.wm_yr_wk
    FROM sales
    LEFT JOIN calendar USING (d)
),

joined AS (
    SELECT
        sales_with_week.id,
        sales_with_week.item_id,
        sales_with_week.store_id,
        sales_with_week.d,
        sales_with_week.sale_date,
        sales_with_week.wm_yr_wk,
        sales_with_week.units_sold,
        prices.sell_price,
        sales_with_week.units_sold * prices.sell_price AS revenue_amount_usd
    FROM sales_with_week
    LEFT JOIN prices
        ON sales_with_week.store_id = prices.store_id
        AND sales_with_week.item_id = prices.item_id
        AND sales_with_week.wm_yr_wk = prices.wm_yr_wk
)

SELECT * FROM joined
