-- ============================================================================
-- 05_phase4_dim_calendar_verification.sql
-- ============================================================================
-- Independent, post-build verification of the dim_calendar warehouse model.
-- Re-runnable any time. Sections are independent (run individually in Snowsight
-- or top-to-bottom). Section 4 is a single-row PASS/FAIL rollup for fast triage.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Section 1: Key uniqueness + row count + date range
-- ----------------------------------------------------------------------------
-- Expectations:
--   row_count = unique_date_keys = unique_calendar_dates  -> no MD5 collisions,
--   no duplicate natural keys, no nulls in either key column.
-- earliest_date / latest_date confirm dim coverage matches what's been
-- extracted to Snowflake to date.

SELECT
    COUNT(*)                                                                 AS row_count,
    COUNT(DISTINCT date_key)                                                 AS unique_date_keys,
    COUNT(DISTINCT calendar_date)                                            AS unique_calendar_dates,
    MIN(calendar_date)                                                       AS earliest_date,
    MAX(calendar_date)                                                       AS latest_date,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT date_key)
         AND COUNT(*) = COUNT(DISTINCT calendar_date)
        THEN 'PASS - row count = unique date_keys = unique calendar_dates'
        ELSE 'FAIL - duplicates exist somewhere'
    END                                                                      AS uniqueness_status
FROM RETAIL_DB.WAREHOUSE.DIM_CALENDAR;


-- ----------------------------------------------------------------------------
-- Section 2: Five-row attribute eyeball (informational)
-- ----------------------------------------------------------------------------
-- Three known holidays + one weekend + one ordinary weekday. Quickly verifies
-- the derived attributes (is_weekend, is_holiday, day_name, event columns)
-- are computing correctly against well-known dates.

SELECT
    date_key,
    calendar_date,
    year,
    quarter,
    month,
    month_name,
    day_of_month,
    day_of_week,
    day_name,
    week_of_year,
    is_weekend,
    wm_yr_wk,
    event_name_1,
    event_type_1,
    is_holiday,
    snap_ca,
    snap_tx,
    snap_wi
FROM RETAIL_DB.WAREHOUSE.DIM_CALENDAR
WHERE calendar_date IN (
    '2011-12-25',  -- Christmas (Sunday, holiday)
    '2012-07-04',  -- Independence Day (Wednesday, holiday)
    '2013-11-28',  -- Thanksgiving (Thursday, holiday)
    '2013-08-17',  -- Random Saturday (weekend, no event)
    '2013-03-15'   -- Random Friday (no event, no weekend)
)
ORDER BY calendar_date;


-- ----------------------------------------------------------------------------
-- Section 3: Distribution sanity checks (informational)
-- ----------------------------------------------------------------------------
-- Confirms:
--   - is_weekend rate ~28.6% (2 out of 7 days). Significantly off would mean
--     the DAYNAME-based derivation has a convention bug.
--   - is_holiday rate is small but non-zero. M5 has ~14 distinct named events.
--   - distinct event names looks sensible (Christmas, Thanksgiving, etc.).

SELECT
    COUNT(*)                                                              AS total_days,
    SUM(CASE WHEN is_weekend THEN 1 ELSE 0 END)                           AS weekend_days,
    ROUND(100.0 * SUM(CASE WHEN is_weekend THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_weekend,
    SUM(CASE WHEN is_holiday THEN 1 ELSE 0 END)                           AS holiday_days,
    ROUND(100.0 * SUM(CASE WHEN is_holiday THEN 1 ELSE 0 END) / COUNT(*), 2) AS pct_holiday,
    COUNT(DISTINCT event_name_1)                                          AS distinct_event_names
FROM RETAIL_DB.WAREHOUSE.DIM_CALENDAR;


-- ----------------------------------------------------------------------------
-- Section 4: PASS/FAIL rollup (single row, fast triage)
-- ----------------------------------------------------------------------------
-- Run this section alone after any dbt build for a one-line status check.

WITH uniqueness AS (
    SELECT
        CASE
            WHEN COUNT(*) = COUNT(DISTINCT date_key)
             AND COUNT(*) = COUNT(DISTINCT calendar_date)
            THEN 'PASS'
            ELSE 'FAIL'
        END AS uniqueness_status
    FROM RETAIL_DB.WAREHOUSE.DIM_CALENDAR
),

weekend_rate AS (
    SELECT
        CASE
            WHEN ROUND(100.0 * SUM(CASE WHEN is_weekend THEN 1 ELSE 0 END) / COUNT(*), 2) BETWEEN 27 AND 30
            THEN 'PASS'
            ELSE 'WARN - weekend rate outside 27-30% band'
        END AS weekend_rate_status
    FROM RETAIL_DB.WAREHOUSE.DIM_CALENDAR
)

SELECT
    uniqueness.uniqueness_status     AS section1_uniqueness,
    weekend_rate.weekend_rate_status AS section3_weekend_rate
FROM uniqueness, weekend_rate;
