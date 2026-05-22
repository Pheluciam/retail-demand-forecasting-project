-- fact_daily_sales.sql
-- Daily sales fact. Grain = one row per item × store × day (~32.9M rows full load).
-- Incremental on sale_date: first build is full load; subsequent builds only newer dates.
-- Clustered on sale_date for date-range query performance in Snowflake.
-- Surrogate keys computed the same way as the three dims (same MD5 input -> matching hash).
-- See DBT_PIPELINE.md for the full walkthrough.

{{ config(
    materialized='incremental',
    unique_key='sale_key',
    cluster_by=['sale_date'],
    on_schema_change='fail'
) }}

WITH source AS (
    SELECT
        item_id,
        store_id,
        sale_date,
        units_sold,
        sell_price,
        revenue_amount_usd
    FROM {{ ref('int_sales_with_prices') }}

    {% if is_incremental() %}
        WHERE sale_date > (
            SELECT COALESCE(MAX(sale_date), '1900-01-01')
            FROM {{ this }}
        )
    {% endif %}
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['item_id', 'store_id', 'sale_date']) }} AS sale_key,
        {{ dbt_utils.generate_surrogate_key(['item_id']) }} AS item_key,
        {{ dbt_utils.generate_surrogate_key(['store_id']) }} AS store_key,
        {{ dbt_utils.generate_surrogate_key(['sale_date']) }} AS date_key,
        item_id,
        store_id,
        sale_date,
        units_sold,
        sell_price,
        revenue_amount_usd
    FROM source
)

SELECT * FROM final
