-- =============================================================================
-- 05_train_forecast_model.sql
-- =============================================================================
-- Trains Snowflake Cortex ML FORECAST on RETAIL_DB.INTERMEDIATE.INT_FORECAST_INPUT
-- and lands a 28-day forecast for every item in
-- RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT.
--
-- Grain: item-level (~3,049 series). Each series is one item with units summed
-- across all 10 stores per day. See int_forecast_input.sql for the rationale
-- on the item-level grain choice (signal quality vs item × store; runtime).
--
-- Downstream: dbt model fact_forecast_daily reads from FORECAST_RAW_OUTPUT,
-- conforms keys to the warehouse star, and exposes the forecast to Power BI.
--
-- Runtime expectation: 60-120 min on XS warehouse with method='best' + evaluate=TRUE.
-- Designed to be kicked off at end of day and left running overnight.
-- =============================================================================

USE ROLE RETAIL_ENGINEER;
USE WAREHOUSE WH_RETAIL;
USE DATABASE RETAIL_DB;
USE SCHEMA INTERMEDIATE;


-- -----------------------------------------------------------------------------
-- Section 1 — Train / retrain the forecast model
-- -----------------------------------------------------------------------------
-- Config tuned for maximum forecast quality (overnight-grade run):
--   method='best'      Cortex ensembles Prophet, ARIMA, ExpSmoothing, GBM and
--                      picks the best fit per series. Snowflake docs recommend
--                      'best' for training data with fewer than 10K series
--                      (we have ~3K, so 'best' is the documented choice).
--   evaluate=TRUE      Cortex runs cross-validation splits to produce accuracy
--                      metrics queryable via SHOW_EVALUATION_METRICS. Adds
--                      training time but produces a portfolio-grade evaluation
--                      artifact.
--   on_error='skip'    Drops series with insufficient history rather than fail.
-- Expected wall-clock at 3K series x ~1,150 days on XS: 60-120 minutes.
-- Designed to be kicked off at end of day and left running overnight.

CREATE OR REPLACE SNOWFLAKE.ML.FORECAST retail_demand_forecast_28d(
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'RETAIL_DB.INTERMEDIATE.INT_FORECAST_INPUT'),
    SERIES_COLNAME => 'SERIES_ID',
    TIMESTAMP_COLNAME => 'SALE_DATE',
    TARGET_COLNAME => 'UNITS_SOLD',
    CONFIG_OBJECT => {'method': 'best', 'evaluate': TRUE, 'on_error': 'skip'}
);


-- -----------------------------------------------------------------------------
-- Section 2 — Generate 28-day forecast and land into a persistent table
-- -----------------------------------------------------------------------------
-- CALL returns a result set; RESULT_SCAN(LAST_QUERY_ID()) captures it.
-- Output columns:
--   SERIES         VARCHAR    — the series_id (= item_id)
--   TS             TIMESTAMP  — the future date
--   FORECAST       FLOAT      — predicted units
--   LOWER_BOUND    FLOAT      — 95% CI lower
--   UPPER_BOUND    FLOAT      — 95% CI upper

CALL retail_demand_forecast_28d!FORECAST(FORECASTING_PERIODS => 28);

CREATE OR REPLACE TABLE RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT AS
SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));


-- -----------------------------------------------------------------------------
-- Section 3 — Smoke test
-- -----------------------------------------------------------------------------
-- Expected: ~85,000 rows (3,049 series × 28 days, minus any Cortex skipped).
-- Forecast horizon: 2014-03-23 through 2014-04-19.

SELECT
    COUNT(*)                                   AS forecast_row_count,
    COUNT(DISTINCT SERIES)                     AS series_count,
    MIN(TS)                                    AS forecast_start,
    MAX(TS)                                    AS forecast_end,
    ROUND(AVG(FORECAST), 2)                    AS avg_predicted_units
FROM RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT;
