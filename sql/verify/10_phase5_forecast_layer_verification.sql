-- =============================================================================
-- 10_phase5_forecast_layer_verification.sql
-- =============================================================================
-- Durable verification for the Phase 5 forecast layer (Snowflake Cortex ML +
-- conformed dbt fact + UNION mart). Re-runnable from Snowsight any time after
-- `05_train_forecast_model.sql` has landed FORECAST_RAW_OUTPUT and
-- `dbt build --select fact_forecast_daily mart_forecast_vs_actual` has run.
-- Each section is an independent SELECT — paste section by section.
--
-- Sections:
--   1. Training input sanity                   (int_forecast_input)
--   2. Cortex raw output integrity             (forecast_raw_output)
--   3. Fact conformance + non-negative floor   (fact_forecast_daily)
--   4. Mart UNION integrity                    (mart_forecast_vs_actual)
--   5. Single-row PASS/FAIL rollup
-- =============================================================================


-- ── Section 1 ── Training input sanity ──────────────────────────────────────
-- int_forecast_input feeds Cortex. Confirms ~3K item series, ~1,150 days,
-- no NULLs in the three columns Cortex consumes, and units >= 0.
-- Expected: series_count ≈ 3,049; min_sale_date 2011-01-29; max_sale_date
-- 2014-03-23; null_count and negative_units both 0.

SELECT
    COUNT(*)                                                          AS row_count,
    COUNT(DISTINCT series_id)                                         AS series_count,
    MIN(sale_date)                                                    AS min_sale_date,
    MAX(sale_date)                                                    AS max_sale_date,
    COUNT(CASE WHEN series_id IS NULL
                 OR sale_date IS NULL
                 OR units_sold IS NULL THEN 1 END)                    AS null_count,
    COUNT(CASE WHEN units_sold < 0 THEN 1 END)                        AS negative_units
FROM RETAIL_DB.INTERMEDIATE.INT_FORECAST_INPUT;


-- ── Section 2 ── Cortex raw output integrity ────────────────────────────────
-- FORECAST_RAW_OUTPUT is the table written by RESULT_SCAN(LAST_QUERY_ID())
-- after `CALL retail_demand_forecast_28d!FORECAST(FORECASTING_PERIODS => 28)`.
-- Four checks in one query:
--   row_count            — total forecast rows. Expected series_count × 28.
--   series_count         — distinct series. Should match Section 1 series_count
--                          (or be very close if any series were skipped by
--                          on_error='skip').
--   horizon_days_min/max — number of forecast rows per series. Both should
--                          equal 28 (every series got a full 28-day horizon).
--   bracket_violations   — rows where LOWER_BOUND > FORECAST or
--                          FORECAST > UPPER_BOUND. Must be 0. Strict-equality
--                          rows (LOWER = FORECAST = UPPER) are degenerate
--                          near-zero-demand series Cortex returns with zero
--                          variance — not bugs, separately counted as
--                          degenerate_ci_series.
--   horizon_alignment    — first forecast date must equal
--                          max(sale_date in int_forecast_input) + 1 day.
-- Reference numbers (2026-05-20 run): row_count = 85,372; series_count = 3,049;
-- horizon both = 28; bracket_violations = 0; alignment 2014-03-24.

WITH per_series AS (
    SELECT SERIES, COUNT(*) AS horizon_days
    FROM RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT
    GROUP BY SERIES
),
training_max AS (
    SELECT MAX(sale_date) AS max_training_date
    FROM RETAIL_DB.INTERMEDIATE.INT_FORECAST_INPUT
)
SELECT
    (SELECT COUNT(*)            FROM RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT) AS row_count,
    (SELECT COUNT(DISTINCT SERIES) FROM RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT) AS series_count,
    (SELECT MIN(horizon_days)   FROM per_series)                                 AS horizon_days_min,
    (SELECT MAX(horizon_days)   FROM per_series)                                 AS horizon_days_max,
    (SELECT COUNT(*)
       FROM RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT
      WHERE LOWER_BOUND > FORECAST
         OR FORECAST    > UPPER_BOUND)                                           AS bracket_violations,
    (SELECT COUNT(DISTINCT SERIES)
       FROM RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT
      WHERE LOWER_BOUND = FORECAST
        AND FORECAST    = UPPER_BOUND)                                           AS degenerate_ci_series,
    (SELECT MIN(TS)::DATE       FROM RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT) AS forecast_start,
    DATEADD(DAY, 1, (SELECT max_training_date FROM training_max))::DATE          AS expected_forecast_start;


-- ── Section 3 ── Fact conformance + non-negative floor ──────────────────────
-- fact_forecast_daily conforms keys from FORECAST_RAW_OUTPUT into the
-- warehouse star. Three checks:
--   row_count_parity   — fact row count should match raw output row count
--                        (minus any rows whose item_id failed dim_item join).
--   item_fk_orphans    — items in fact missing from dim_item. Must be 0.
--   floor_violations   — any forecast_units < 0. Per playbook §1.5 the model
--                        floors negatives at 0, so this MUST be 0.
-- Requires `dbt build --select fact_forecast_daily` to have run.

SELECT
    (SELECT COUNT(*) FROM RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT)             AS raw_output_rows,
    (SELECT COUNT(*) FROM RETAIL_DB.WAREHOUSE.FACT_FORECAST_DAILY)                AS fact_rows,
    (SELECT COUNT(*)
       FROM RETAIL_DB.WAREHOUSE.FACT_FORECAST_DAILY f
       LEFT JOIN RETAIL_DB.WAREHOUSE.DIM_ITEM d
              ON f.item_key = d.item_key
      WHERE d.item_key IS NULL)                                                   AS item_fk_orphans,
    (SELECT COUNT(*)
       FROM RETAIL_DB.WAREHOUSE.FACT_FORECAST_DAILY
      WHERE forecast_units < 0)                                                   AS floor_violations;


-- ── Section 4 ── Mart UNION integrity ───────────────────────────────────────
-- mart_forecast_vs_actual UNIONs actuals (from fact_daily_sales) with forecasts
-- (from fact_forecast_daily) using a series_type discriminator. Four checks:
--   actual_rows / forecast_rows  — split of rows by discriminator.
--   series_type_other            — rows with any value other than 'actual' or
--                                  'forecast'. Must be 0.
--   actual_revenue_parity        — sum of actual revenue in the mart should
--                                  equal sum of revenue in fact_daily_sales.
--   forecast_rows_parity         — forecast row count in the mart should
--                                  equal row count in fact_forecast_daily.

SELECT
    (SELECT COUNT(*) FROM RETAIL_DB.MARTS.MART_FORECAST_VS_ACTUAL
        WHERE series_type = 'actual')                                              AS actual_rows,
    (SELECT COUNT(*) FROM RETAIL_DB.MARTS.MART_FORECAST_VS_ACTUAL
        WHERE series_type = 'forecast')                                            AS forecast_rows,
    (SELECT COUNT(*) FROM RETAIL_DB.MARTS.MART_FORECAST_VS_ACTUAL
        WHERE series_type NOT IN ('actual', 'forecast') OR series_type IS NULL)    AS series_type_other,
    (SELECT SUM(revenue_usd) FROM RETAIL_DB.MARTS.MART_FORECAST_VS_ACTUAL
        WHERE series_type = 'actual')                                              AS mart_actual_revenue,
    (SELECT SUM(revenue_amount_usd) FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES)     AS fact_actual_revenue,
    (SELECT COUNT(*) FROM RETAIL_DB.WAREHOUSE.FACT_FORECAST_DAILY)                 AS fact_forecast_rows;


-- ── Section 5 ── Single-row PASS/FAIL rollup ────────────────────────────────
-- One-row health check covering all four upstream sections. All columns
-- should read 'PASS'. If any FAIL, drop back into the corresponding section
-- to see the offending values.

WITH checks AS (
    SELECT
        -- Section 1: input has no nulls and no negatives
        (SELECT COUNT(CASE WHEN series_id IS NULL OR sale_date IS NULL
                                OR units_sold IS NULL OR units_sold < 0
                           THEN 1 END)
           FROM RETAIL_DB.INTERMEDIATE.INT_FORECAST_INPUT) = 0
            AS input_clean_pass,

        -- Section 2: every series got exactly 28 forecast rows, and bracket holds
        (SELECT MIN(horizon_days) = 28 AND MAX(horizon_days) = 28
           FROM (SELECT COUNT(*) AS horizon_days
                   FROM RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT
                  GROUP BY SERIES))
            AS horizon_complete_pass,

        (SELECT COUNT(*)
           FROM RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT
          WHERE LOWER_BOUND > FORECAST OR FORECAST > UPPER_BOUND) = 0
            AS bracket_pass,

        -- Section 3: floor at 0 holds, no FK orphans
        (SELECT COUNT(*) FROM RETAIL_DB.WAREHOUSE.FACT_FORECAST_DAILY
          WHERE forecast_units < 0) = 0
            AS floor_pass,

        (SELECT COUNT(*)
           FROM RETAIL_DB.WAREHOUSE.FACT_FORECAST_DAILY f
           LEFT JOIN RETAIL_DB.WAREHOUSE.DIM_ITEM d ON f.item_key = d.item_key
          WHERE d.item_key IS NULL) = 0
            AS fact_fk_pass,

        -- Section 4: mart discriminator is clean and revenue reconciles
        (SELECT COUNT(*) FROM RETAIL_DB.MARTS.MART_FORECAST_VS_ACTUAL
          WHERE series_type NOT IN ('actual', 'forecast') OR series_type IS NULL) = 0
            AS series_type_pass,

        (SELECT SUM(revenue_usd) FROM RETAIL_DB.MARTS.MART_FORECAST_VS_ACTUAL
          WHERE series_type = 'actual')
        = (SELECT SUM(revenue_amount_usd) FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES)
            AS actual_revenue_parity_pass
)
SELECT
    CASE WHEN input_clean_pass            THEN 'PASS' ELSE 'FAIL' END AS input_clean,
    CASE WHEN horizon_complete_pass       THEN 'PASS' ELSE 'FAIL' END AS horizon_complete,
    CASE WHEN bracket_pass                THEN 'PASS' ELSE 'FAIL' END AS ci_bracket,
    CASE WHEN floor_pass                  THEN 'PASS' ELSE 'FAIL' END AS fact_floor,
    CASE WHEN fact_fk_pass                THEN 'PASS' ELSE 'FAIL' END AS fact_fk,
    CASE WHEN series_type_pass            THEN 'PASS' ELSE 'FAIL' END AS series_type_clean,
    CASE WHEN actual_revenue_parity_pass  THEN 'PASS' ELSE 'FAIL' END AS actual_revenue_parity
FROM checks;
