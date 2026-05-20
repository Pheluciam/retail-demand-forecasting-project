-- dim_calendar.sql
-- Calendar dimension. One row per date.
-- Materialised as table (per dbt_project.yml warehouse default).
-- Surrogate key via dbt_utils.generate_surrogate_key for consistency with other dims.
-- ISO date variants (DAYOFWEEKISO, WEEKISO) used for session-parameter independence.
--
-- Coverage: historical M5 dates from stg_m5_calendar PLUS a 60-day future
-- horizon to support forecast date slicing in Power BI (Forecast vs Actual
-- page joins forecast.date_key → dim_calendar.date_key). Future rows carry
-- date-derived attributes only; M5-specific attrs (d, wm_yr_wk, event_*,
-- snap_*) are NULL — see _warehouse__models.yml tests scoped historical-only.
-- See DBT_PIPELINE.md for the full walkthrough.

WITH source AS (
    SELECT
        calendar_date,
        d,
        wm_yr_wk,
        event_name_1,
        event_type_1,
        event_name_2,
        event_type_2,
        snap_ca,
        snap_tx,
        snap_wi
    FROM {{ ref('stg_m5_calendar') }}
),

future_dates AS (
    SELECT
        DATEADD(day, seq4() + 1, (SELECT MAX(calendar_date) FROM source))::DATE AS calendar_date,
        NULL::VARCHAR AS d,
        NULL::NUMBER  AS wm_yr_wk,
        NULL::VARCHAR AS event_name_1,
        NULL::VARCHAR AS event_type_1,
        NULL::VARCHAR AS event_name_2,
        NULL::VARCHAR AS event_type_2,
        NULL::NUMBER  AS snap_ca,
        NULL::NUMBER  AS snap_tx,
        NULL::NUMBER  AS snap_wi
    FROM TABLE(GENERATOR(ROWCOUNT => 60))
),

combined AS (
    SELECT * FROM source
    UNION ALL
    SELECT * FROM future_dates
),

enriched AS (
    SELECT
        calendar_date,
        d,

        DATE_PART('year', calendar_date)    AS year,
        DATE_PART('quarter', calendar_date) AS quarter,
        DATE_PART('month', calendar_date)   AS month,
        MONTHNAME(calendar_date)            AS month_name,
        DATE_PART('day', calendar_date)     AS day_of_month,
        DAYOFWEEKISO(calendar_date)         AS day_of_week,
        DAYNAME(calendar_date)              AS day_name,
        WEEKISO(calendar_date)              AS week_of_year,

        CASE
            WHEN DAYNAME(calendar_date) IN ('Sat', 'Sun')
            THEN TRUE
            ELSE FALSE
        END AS is_weekend,

        wm_yr_wk,

        event_name_1,
        event_type_1,
        event_name_2,
        event_type_2,

        CASE
            WHEN event_name_1 IS NOT NULL OR event_name_2 IS NOT NULL
            THEN TRUE
            ELSE FALSE
        END AS is_holiday,

        snap_ca,
        snap_tx,
        snap_wi
    FROM combined
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['calendar_date']) }} AS date_key,
        enriched.*
    FROM enriched
)

SELECT * FROM final
