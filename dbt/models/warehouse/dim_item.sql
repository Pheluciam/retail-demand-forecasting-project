-- dim_item.sql
-- Item dimension. One row per distinct M5 item (~3,049 rows).
-- Surrogate item_key via dbt_utils.generate_surrogate_key on item_id.
-- dept_id and cat_id come straight from staging — no string parsing.
-- See DBT_PIPELINE.md for the full walkthrough.

WITH source AS (
    SELECT DISTINCT
        item_id,
        dept_id,
        cat_id
    FROM {{ ref('stg_m5_sales_train') }}
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['item_id']) }} AS item_key,
        item_id,
        dept_id,
        cat_id
    FROM source
)

SELECT * FROM final
