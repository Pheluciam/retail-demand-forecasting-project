-- ============================================================================
-- 06_phase4_dim_item_verification.sql
-- ============================================================================
-- Independent, post-build verification of the dim_item warehouse model.
-- Re-runnable any time. Sections are independent (run individually in Snowsight
-- or top-to-bottom). Section 4 is a single-row PASS/FAIL rollup for fast triage.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- Section 1: Key uniqueness + row count
-- ----------------------------------------------------------------------------
-- Expectations:
--   row_count = unique_item_keys = unique_item_ids = 3,049
-- If unique_item_keys < row_count -> MD5 collision (vanishingly unlikely).
-- If unique_item_ids < row_count  -> same item_id appears with different
-- dept_id/cat_id (data-quality issue worth chasing upstream).

SELECT
    COUNT(*)                                                                 AS row_count,
    COUNT(DISTINCT item_key)                                                 AS unique_item_keys,
    COUNT(DISTINCT item_id)                                                  AS unique_item_ids,
    CASE
        WHEN COUNT(*) = COUNT(DISTINCT item_key)
         AND COUNT(*) = COUNT(DISTINCT item_id)
         AND COUNT(*) = 3049
        THEN 'PASS - row count = unique item_keys = unique item_ids = 3,049'
        ELSE 'FAIL - investigate row_count / uniqueness / expected 3,049'
    END                                                                      AS uniqueness_status
FROM RETAIL_DB.WAREHOUSE.DIM_ITEM;


-- ----------------------------------------------------------------------------
-- Section 2: Hierarchy cardinality (informational)
-- ----------------------------------------------------------------------------
-- Expectations:
--   distinct_categories  = 3   (HOBBIES, FOODS, HOUSEHOLD)
--   distinct_departments = 7   (FOODS_1/2/3, HOBBIES_1/2, HOUSEHOLD_1/2)
-- These are M5 invariants. Drift here means raw source has shifted.

SELECT
    COUNT(DISTINCT cat_id)  AS distinct_categories,
    COUNT(DISTINCT dept_id) AS distinct_departments
FROM RETAIL_DB.WAREHOUSE.DIM_ITEM;


-- ----------------------------------------------------------------------------
-- Section 3: Five-row attribute eyeball (informational)
-- ----------------------------------------------------------------------------
-- One row per item across the three categories. Confirms:
--   - item_key is a 32-char MD5 hex
--   - dept_id prefix matches cat_id (e.g. dept_id = HOBBIES_1 -> cat_id = HOBBIES)
--   - item_id naming convention <DEPT>_<NNN>

SELECT *
FROM RETAIL_DB.WAREHOUSE.DIM_ITEM
ORDER BY cat_id, dept_id, item_id
LIMIT 5;


-- ----------------------------------------------------------------------------
-- Section 4: PASS/FAIL rollup (single row, fast triage)
-- ----------------------------------------------------------------------------
-- Run this section alone after any dbt build for a one-line status check.

WITH uniqueness AS (
    SELECT
        CASE
            WHEN COUNT(*) = COUNT(DISTINCT item_key)
             AND COUNT(*) = COUNT(DISTINCT item_id)
             AND COUNT(*) = 3049
            THEN 'PASS'
            ELSE 'FAIL'
        END AS uniqueness_status
    FROM RETAIL_DB.WAREHOUSE.DIM_ITEM
),

hierarchy AS (
    SELECT
        CASE
            WHEN COUNT(DISTINCT cat_id) = 3
             AND COUNT(DISTINCT dept_id) = 7
            THEN 'PASS'
            ELSE 'FAIL - cat/dept cardinality drift from M5 invariants'
        END AS hierarchy_status
    FROM RETAIL_DB.WAREHOUSE.DIM_ITEM
)

SELECT
    uniqueness.uniqueness_status AS section1_uniqueness,
    hierarchy.hierarchy_status   AS section2_hierarchy
FROM uniqueness, hierarchy;
