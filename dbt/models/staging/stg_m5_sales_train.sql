-- Staging view for M5 daily sales. One row per item × store × day.
-- Joins to stg_m5_calendar to translate the M5 'd_NNNN' identifier
-- into a real DATE (sale_date).
-- Materialises to STAGING.STG_M5_SALES_TRAIN.

WITH source AS (

    SELECT * FROM {{ source('m5', 'SALES_TRAIN') }}

),

calendar AS (

    SELECT
        d,
        calendar_date
    FROM {{ ref('stg_m5_calendar') }}

),

joined AS (

    SELECT
        s.id,
        s.item_id,
        s.dept_id,
        s.cat_id,
        s.store_id,
        s.state_id,
        s.d,
        c.calendar_date AS sale_date,
        s.sales AS units_sold
    FROM source AS s
    LEFT JOIN calendar AS c
        ON s.d = c.d

)

SELECT * FROM joined
