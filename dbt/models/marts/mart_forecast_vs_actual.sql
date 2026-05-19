-- mart_forecast_vs_actual.sql
-- Powers the Power BI Forecast vs Actual page.
-- UNIONs actual daily sales (aggregated from fact_daily_sales to item × day grain
-- to match the forecast's grain) with the forecast fact. Discriminator column
-- 'series_type' lets BI visuals slice or layer the two side by side.
--
-- Grain: one row per (item × observation_date × series_type).
-- Two series_type values: 'actual' (history) and 'forecast' (future).

{{ config(
    materialized='table'
) }}

WITH actuals AS (
    SELECT
        f.date_key,
        f.item_key,
        f.sale_date                          AS observation_date,
        f.item_id,
        SUM(f.units_sold)                    AS units,
        SUM(f.revenue_amount_usd)            AS revenue_usd,
        CAST(NULL AS FLOAT)                  AS units_lower_95,
        CAST(NULL AS FLOAT)                  AS units_upper_95,
        'actual'                             AS series_type
    FROM {{ ref('fact_daily_sales') }} f
    GROUP BY f.date_key, f.item_key, f.sale_date, f.item_id
),

forecasts AS (
    SELECT
        f.date_key,
        f.item_key,
        f.forecast_date                      AS observation_date,
        f.item_id,
        f.forecast_units                     AS units,
        f.forecast_revenue_usd               AS revenue_usd,
        f.forecast_units_lower_95            AS units_lower_95,
        f.forecast_units_upper_95            AS units_upper_95,
        'forecast'                           AS series_type
    FROM {{ ref('fact_forecast_daily') }} f
)

SELECT * FROM actuals
UNION ALL
SELECT * FROM forecasts
