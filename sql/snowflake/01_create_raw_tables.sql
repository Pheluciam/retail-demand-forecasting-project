-- ============================================================================
-- 01_create_raw_tables.sql  (Snowflake)
-- ============================================================================
-- Creates the three raw tables in RETAIL_DB.RAW that mirror the Azure SQL
-- raw.* tables. Loaded by scripts/extract_azure_to_snowflake.py.
--
-- Idempotent: CREATE OR REPLACE TABLE atomically drops + recreates the table.
-- *** DESTRUCTIVE *** — running this wipes any data already loaded in these
-- tables. Safe in development; do NOT re-run blindly once a backfill is in place.
--
-- Run as RETAIL_ENGINEER (set up by 00_provision_account.sql).
-- Phase: 2 — Snowflake + extraction
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. Session context — make sure we land objects in the right place.
-- ----------------------------------------------------------------------------
USE ROLE      RETAIL_ENGINEER;
USE WAREHOUSE WH_RETAIL;
USE DATABASE  RETAIL_DB;
USE SCHEMA    RAW;


-- ----------------------------------------------------------------------------
-- 1. calendar
-- ----------------------------------------------------------------------------
-- Source: Azure SQL raw.calendar  (1,969 rows)
-- One row per date with Walmart fiscal week + event/holiday metadata.
-- Loaded once during Phase 2 backfill; not part of the incremental walk.
CREATE OR REPLACE TABLE RETAIL_DB.RAW.CALENDAR (
    date          VARCHAR(10) NOT NULL  COMMENT 'YYYY-MM-DD as text; cast to DATE in dbt staging',
    wm_yr_wk      INTEGER     NOT NULL  COMMENT 'Walmart fiscal year+week, e.g. 11101 = year 2011 week 01',
    weekday       VARCHAR(10) NOT NULL  COMMENT '''Saturday'', ''Sunday'', etc.',
    wday          SMALLINT    NOT NULL  COMMENT '1-7 weekday number',
    month         SMALLINT    NOT NULL  COMMENT '1-12',
    year          SMALLINT    NOT NULL  COMMENT 'e.g. 2016',
    d             VARCHAR(10) NOT NULL  COMMENT '''d_1'' .. ''d_1941'' join key to sales_train.d',
    event_name_1  VARCHAR(50)           COMMENT 'Nullable: e.g. ''SuperBowl''; usually blank',
    event_type_1  VARCHAR(20)           COMMENT '''Sporting'', ''Cultural'', ''National'', ''Religious''',
    event_name_2  VARCHAR(50)           COMMENT 'Some dates have a 2nd event',
    event_type_2  VARCHAR(20),
    snap_CA       SMALLINT    NOT NULL  COMMENT 'SNAP benefits day flag (0/1) — California',
    snap_TX       SMALLINT    NOT NULL  COMMENT 'SNAP — Texas',
    snap_WI       SMALLINT    NOT NULL  COMMENT 'SNAP — Wisconsin',
    -- Audit metadata
    loaded_at     TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() NOT NULL
                                          COMMENT 'When this row was inserted by the extract job'
)
COMMENT = 'M5 Walmart calendar — 1 row per date, fiscal calendar + events + SNAP flags';


-- ----------------------------------------------------------------------------
-- 2. sell_prices
-- ----------------------------------------------------------------------------
-- Source: Azure SQL raw.sell_prices  (6,841,121 rows)
-- One row per (store × item × week) with the price charged.
-- Already long format — no unpivot needed.
CREATE OR REPLACE TABLE RETAIL_DB.RAW.SELL_PRICES (
    store_id    VARCHAR(10)   NOT NULL  COMMENT 'e.g. ''CA_1'', ''TX_3''',
    item_id     VARCHAR(20)   NOT NULL  COMMENT 'e.g. ''HOBBIES_1_001''',
    wm_yr_wk    INTEGER       NOT NULL  COMMENT 'Walmart fiscal year+week — joins to calendar.wm_yr_wk',
    sell_price  NUMBER(10,4)  NOT NULL  COMMENT 'Price (USD). NUMBER (not FLOAT) — exact arithmetic on $',
    -- Audit metadata
    loaded_at   TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() NOT NULL
                                        COMMENT 'When this row was inserted by the extract job'
)
COMMENT = 'M5 Walmart weekly sell prices — store × item × week, ~6.8M rows';


-- ----------------------------------------------------------------------------
-- 3. sales_train
-- ----------------------------------------------------------------------------
-- Source: Azure SQL raw.sales_train  (59,181,090 rows)
-- Already in LONG format (Python unpivoted during Phase 1 load).
-- Expected total: 30,490 series × 1,941 day cols = 59,181,090.
-- This is the big table — most of the extract effort lives here.
CREATE OR REPLACE TABLE RETAIL_DB.RAW.SALES_TRAIN (
    id        VARCHAR(50) NOT NULL  COMMENT 'M5 series id, e.g. ''HOBBIES_1_001_CA_1_evaluation''',
    item_id   VARCHAR(20) NOT NULL  COMMENT 'e.g. ''HOBBIES_1_001''',
    dept_id   VARCHAR(20) NOT NULL  COMMENT 'e.g. ''HOBBIES_1''',
    cat_id    VARCHAR(20) NOT NULL  COMMENT 'e.g. ''HOBBIES''',
    store_id  VARCHAR(10) NOT NULL  COMMENT 'e.g. ''CA_1''',
    state_id  VARCHAR(5)  NOT NULL  COMMENT '''CA'', ''TX'', ''WI''',
    d         VARCHAR(10) NOT NULL  COMMENT '''d_1'' .. ''d_1941'' — join key to calendar.d',
    sales     INTEGER     NOT NULL  COMMENT 'Units sold that day',
    -- Audit metadata
    loaded_at TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() NOT NULL
                                      COMMENT 'When this row was inserted by the extract job'
)
COMMENT = 'M5 Walmart daily unit sales — long format (item × store × day), ~59.2M rows';


-- ----------------------------------------------------------------------------
-- 4. Verify — confirm all three tables exist with expected column counts.
-- ----------------------------------------------------------------------------
SELECT
    table_name,
    row_count,
    bytes,
    created,
    comment
FROM RETAIL_DB.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'RAW'
  AND table_name IN ('CALENDAR', 'SELL_PRICES', 'SALES_TRAIN')
ORDER BY table_name;
