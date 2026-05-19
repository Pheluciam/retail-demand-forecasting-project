-- agg_sales_daily.sql
-- Day-grain aggregate fact over fact_daily_sales.
-- Wired as a user-defined aggregation in Power BI to serve trend visuals
-- without scanning the 32.9M-row fact.

{{ config(
    materialized='table'
) }}

WITH source AS (
    SELECT *
    FROM {{ ref('fact_daily_sales') }}
),

aggregated AS (
    SELECT
        date_key,
        SUM(units_sold)                                              AS total_units_sold,
        SUM(revenue_amount_usd)                                      AS total_revenue_usd,
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN item_id  END)   AS active_item_count,
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN store_id END)   AS active_store_count
    FROM source
    GROUP BY date_key
)

SELECT * FROM aggregated
