-- agg_sales_daily_item_cat.sql
-- Day × item-category aggregate fact over fact_daily_sales.
-- Wired as a user-defined aggregation in Power BI so category-grouped visuals
-- can answer from this rollup instead of scanning the 32.9M-row fact.

{{ config(
    materialized='table'
) }}

WITH source AS (
    SELECT
        f.date_key,
        i.cat_id,
        f.item_id,
        f.store_id,
        f.units_sold,
        f.revenue_amount_usd
    FROM {{ ref('fact_daily_sales') }} f
    INNER JOIN {{ ref('dim_item') }} i
        USING (item_key)
),

aggregated AS (
    SELECT
        date_key,
        cat_id,
        SUM(units_sold)                                              AS total_units_sold,
        SUM(revenue_amount_usd)                                      AS total_revenue_usd,
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN item_id  END)   AS active_item_count,
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN store_id END)   AS active_store_count
    FROM source
    GROUP BY date_key, cat_id
)

SELECT * FROM aggregated
