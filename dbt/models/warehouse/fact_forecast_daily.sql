-- fact_forecast_daily.sql
-- Daily forecast fact at item × day grain.
-- Sourced from the Snowflake Cortex ML FORECAST output table
-- (RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT, created by 05_train_forecast_model.sql).
-- Conforms surrogate keys to the warehouse star.
--
-- Note on date_key: forecast dates are FUTURE relative to fact_daily_sales
-- (2014-03-23 onwards). dim_calendar currently ends 2014-03-22, so date_key
-- on this fact will NOT have matches in dim_calendar. The relationships test
-- on date_key is intentionally skipped. To enable BI-side date slicing, extend
-- dim_calendar to cover the forecast horizon (deferred — known follow-up).

{{ config(
    materialized='table'
) }}

WITH source AS (
    SELECT
        series AS item_id,
        CAST(ts AS DATE) AS forecast_date,
        forecast AS raw_forecast_units,
        lower_bound AS raw_lower_95,
        upper_bound AS raw_upper_95
    FROM {{ source('forecast_outputs', 'forecast_raw_output') }}
),

recent_prices AS (
    -- Average observed sell_price per item over the last 28 days of actuals.
    -- Used to convert forecast units into a forecast revenue estimate.
    SELECT
        item_id,
        AVG(sell_price) AS avg_recent_price
    FROM {{ ref('int_sales_with_prices') }}
    WHERE
        sell_price IS NOT NULL
        AND sale_date >= (
            SELECT DATEADD(DAY, -28, MAX(sale_date))
            FROM {{ ref('int_sales_with_prices') }}
        )
    GROUP BY item_id
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['s.item_id', 's.forecast_date']) }} AS forecast_key,
        {{ dbt_utils.generate_surrogate_key(['s.item_id']) }} AS item_key,
        {{ dbt_utils.generate_surrogate_key(['s.forecast_date']) }} AS date_key,
        s.item_id,
        s.forecast_date,
        -- Floor at 0: Cortex can occasionally predict slight negatives on
        -- low-volume series, which is nonsensical for units sold.
        GREATEST(s.raw_forecast_units, 0) AS forecast_units,
        GREATEST(s.raw_forecast_units * COALESCE(p.avg_recent_price, 0), 0) AS forecast_revenue_usd,
        GREATEST(s.raw_lower_95, 0) AS forecast_units_lower_95,
        GREATEST(s.raw_upper_95, 0) AS forecast_units_upper_95
    FROM source AS s
    LEFT JOIN recent_prices AS p ON s.item_id = p.item_id
)

SELECT * FROM final
