-- mart_executive_overview.sql
-- Pre-aggregated daily summary for the Power BI dashboard home page.
-- Grain: one row per sale_date. Source: WAREHOUSE.fact_daily_sales.
-- Walkthrough: DBT_PIPELINE.md → "mart_executive_overview".

{{ config(
    materialized='table'
) }}

WITH source AS (
    SELECT *
    FROM {{ ref('fact_daily_sales') }}
),

aggregated AS (
    SELECT
        sale_date,
        SUM(units_sold)                                              AS total_units_sold,
        SUM(revenue_amount_usd)                                      AS total_revenue_usd,
        -- 'active' = sold at least one unit that day; excludes on-shelf-didn't-sell rows.
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN item_id  END)   AS active_item_count,
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN store_id END)   AS active_store_count
    FROM source
    GROUP BY sale_date
)

SELECT * FROM aggregated
