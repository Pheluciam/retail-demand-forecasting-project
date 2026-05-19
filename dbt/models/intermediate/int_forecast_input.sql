-- int_forecast_input.sql
-- Slim historical view that feeds Snowflake Cortex ML FORECAST.
-- Grain: one row per (item × day). Units aggregated across all stores per item.
-- ~3,049 series × ~1,150 days = ~3.4M training rows.
--
-- Design choice — item-level grain (not item × store):
--   Aggregating units across stores produces stronger signal per series because
--   each item's daily demand across all 10 stores is more stationary than per-store
--   splits. Standard retail forecasting pattern when stores share similar SKU mixes.
--   Trains in ~3-5 min on XS warehouse vs ~2-5 hrs at item × store grain.

WITH aggregated AS (
    SELECT
        item_id,
        sale_date,
        SUM(units_sold) AS units_sold
    FROM {{ ref('fact_daily_sales') }}
    GROUP BY item_id, sale_date
)

SELECT
    item_id  AS series_id,
    sale_date,
    units_sold
FROM aggregated
WHERE units_sold IS NOT NULL
