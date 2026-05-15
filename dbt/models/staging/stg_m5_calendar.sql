-- Staging view for the M5 calendar dimension. One row per date.
-- Materialises to STAGING.STG_M5_CALENDAR via dbt_project.yml defaults
-- and the generate_schema_name macro.

SELECT
    -- raw.date is VARCHAR; cast to DATE so downstream joins work.
    CAST(date AS DATE) AS calendar_date,
    wm_yr_wk,
    weekday,
    wday,
    month,
    year,
    d,
    event_name_1,
    event_type_1,
    event_name_2,
    event_type_2,
    snap_CA AS snap_ca,
    snap_TX AS snap_tx,
    snap_WI AS snap_wi
FROM {{ source('m5', 'CALENDAR') }}
