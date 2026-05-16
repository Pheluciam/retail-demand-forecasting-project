-- ============================================================================
-- 07_phase4_dim_store_verification.sql
-- ============================================================================
-- Independent, post-build verification of the dim_store warehouse model.
-- Re-runnable any time. Sections are independent (run individually in Snowsight
-- or top-to-bottom). Section 4 is a single-row PASS/FAIL rollup for fast triage.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Section 1: Key uniqueness + row count
-- ----------------------------------------------------------------------------
-- Expectations:
--   row_count = unique_store_keys = unique_store_ids = 10
-- If unique_store_keys < row_count -> MD5 collision (vanishingly unlikely).
-- If unique_store_ids < row_count  -> same store_id appears with different
-- state_id (data-quality issue worth chasing upstream).

SELECT
    COUNT(*)                                                                 AS row_count,
    COUNT(DISTINCT store_key)                                                AS unique_store_keys,
    COUNT(DISTINCT store_id)                                                 AS unique_store_ids,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT store_key)
         AND COUNT(*) = COUNT(DISTINCT store_id)
         AND COUNT(*) = 10
        THEN 'PASS - row count = unique store_keys = unique store_ids = 10'
        ELSE 'FAIL - investigate row_count / uniqueness / expected 10'
    END                                                                      AS uniqueness_status
FROM RETAIL_DB.WAREHOUSE.DIM_STORE;


-- ----------------------------------------------------------------------------
-- Section 2: State distribution (informational)
-- ----------------------------------------------------------------------------
-- Expectations (M5 invariants):
--   CA = 4 stores, TX = 3 stores, WI = 3 stores. Total = 10.

SELECT
    state_id,
    COUNT(*) AS store_count
FROM RETAIL_DB.WAREHOUSE.DIM_STORE
GROUP BY state_id
ORDER BY state_id;


-- ----------------------------------------------------------------------------
-- Section 3: Full table eyeball (informational)
-- ----------------------------------------------------------------------------
-- Only 10 rows — return the whole thing. Confirms:
--   - store_key is a 32-char MD5 hex
--   - store_id naming convention <STATE>_<N>
--   - state_id prefix matches store_id

SELECT *
FROM RETAIL_DB.WAREHOUSE.DIM_STORE
ORDER BY state_id, store_id;


-- ----------------------------------------------------------------------------
-- Section 4: PASS/FAIL rollup (single row, fast triage)
-- ----------------------------------------------------------------------------
-- Run this section alone after any dbt build for a one-line status check.

WITH uniqueness AS (
    SELECT
        CASE
            WHEN COUNT(*) = COUNT(DISTINCT store_key)
             AND COUNT(*) = COUNT(DISTINCT store_id)
             AND COUNT(*) = 10
            THEN 'PASS'
            ELSE 'FAIL'
        END AS uniqueness_status
    FROM RETAIL_DB.WAREHOUSE.DIM_STORE
),

state_distribution AS (
    SELECT
        CASE
            WHEN COUNT(DISTINCT state_id) = 3
             AND MAX(CASE WHEN state_id = 'CA' THEN cnt END) = 4
             AND MAX(CASE WHEN state_id = 'TX' THEN cnt END) = 3
             AND MAX(CASE WHEN state_id = 'WI' THEN cnt END) = 3
            THEN 'PASS'
            ELSE 'FAIL - state distribution drift from M5 invariants (CA=4, TX=3, WI=3)'
        END AS state_distribution_status
    FROM (
        SELECT state_id, COUNT(*) AS cnt
        FROM RETAIL_DB.WAREHOUSE.DIM_STORE
        GROUP BY state_id
    )
)

SELECT
    uniqueness.uniqueness_status                 AS section1_uniqueness,
    state_distribution.state_distribution_status AS section2_state_distribution
FROM uniqueness, state_distribution;
