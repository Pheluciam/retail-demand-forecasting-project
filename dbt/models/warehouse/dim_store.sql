-- dim_store.sql
-- Store dimension. One row per distinct M5 store (~10 rows).
-- Surrogate store_key via dbt_utils.generate_surrogate_key on store_id.
-- state_id comes straight from staging — no string parsing.
-- See DBT_PIPELINE.md for the full walkthrough.

WITH source AS (
    SELECT DISTINCT
        store_id,
        state_id
    FROM {{ ref('stg_m5_sales_train') }}
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['store_id']) }} AS store_key,
        store_id,
        state_id
    FROM source
)

SELECT * FROM final
