-- ============================================================================
-- 01_create_raw_tables.sql
-- ============================================================================
-- Creates the `raw` schema and three raw tables for the M5 dataset
-- in Azure SQL Database.
--
-- Idempotent: drops the tables (if they exist) before recreating them.
-- Safe to re-run during development if the schema needs to change.
--
-- Executed by: scripts/create_raw_tables.py
-- ============================================================================


-- Batch 1: create the `raw` schema if it doesn't already exist
-- CREATE SCHEMA must be the first statement in its own batch, so we
-- wrap it in EXEC() to allow the IF NOT EXISTS check to live with it.
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'raw')
    EXEC('CREATE SCHEMA raw');
GO


-- Batch 2: drop any existing tables (idempotency)
-- Order matters once we add foreign keys later — drop children before parents.
-- For now there are no FKs so order is cosmetic.
-- Using modern (SQL Server 2016+) `DROP TABLE IF EXISTS` syntax.
DROP TABLE IF EXISTS raw.sales_train;
DROP TABLE IF EXISTS raw.sell_prices;
DROP TABLE IF EXISTS raw.calendar;
GO


-- Batch 3: calendar
-- Source: data/raw/calendar.csv  (1,969 rows)
-- One row per date with WMart fiscal week + event/holiday metadata.
CREATE TABLE raw.calendar (
    date          NVARCHAR(10) NOT NULL,   -- 'YYYY-MM-DD' as text, cast to DATE in dbt staging
    wm_yr_wk      INT          NOT NULL,   -- WMart fiscal year+week (e.g. 11101)
    weekday       NVARCHAR(10) NOT NULL,   -- 'Saturday', 'Sunday', etc.
    wday          TINYINT      NOT NULL,   -- 1-7 weekday number
    month         TINYINT      NOT NULL,   -- 1-12
    year          SMALLINT     NOT NULL,   -- e.g. 2016
    d             NVARCHAR(10) NOT NULL,   -- 'd_1' .. 'd_1941' (join key to sales_train)
    event_name_1  NVARCHAR(50) NULL,       -- nullable: e.g. 'SuperBowl', often blank
    event_type_1  NVARCHAR(20) NULL,       -- 'Sporting', 'Cultural', 'National', 'Religious'
    event_name_2  NVARCHAR(50) NULL,       -- some dates have 2 events
    event_type_2  NVARCHAR(20) NULL,
    snap_CA       TINYINT      NOT NULL,   -- SNAP benefits day flag (0/1) for California
    snap_TX       TINYINT      NOT NULL,   -- Texas
    snap_WI       TINYINT      NOT NULL    -- Wisconsin
);
GO


-- Batch 4: sell_prices
-- Source: data/raw/sell_prices.csv  (6,841,121 rows)
-- One row per (store × item × week) with the price charged.
-- Already in long format — loads straight from the CSV.
CREATE TABLE raw.sell_prices (
    store_id    NVARCHAR(10)  NOT NULL,    -- e.g. 'CA_1', 'TX_3'
    item_id     NVARCHAR(20)  NOT NULL,    -- e.g. 'HOBBIES_1_001'
    wm_yr_wk    INT           NOT NULL,    -- join key to calendar.wm_yr_wk
    sell_price  DECIMAL(10,4) NOT NULL     -- price (USD). DECIMAL avoids float rounding on $$
)
WITH (DATA_COMPRESSION = PAGE);  -- ~50-70% disk savings on 6.8M-row table
GO


-- Batch 5: sales_train
-- Source: data/raw/sales_train_evaluation.csv  (30,490 rows × 1,941 day cols)
-- LOADED IN LONG FORMAT — Python unpivots the wide CSV before insert.
-- Expected row count after load: 30,490 × 1,941 = 59,180,090
CREATE TABLE raw.sales_train (
    id        NVARCHAR(50) NOT NULL,       -- e.g. 'HOBBIES_1_001_CA_1_evaluation'
    item_id   NVARCHAR(20) NOT NULL,       -- e.g. 'HOBBIES_1_001'
    dept_id   NVARCHAR(20) NOT NULL,       -- e.g. 'HOBBIES_1'
    cat_id    NVARCHAR(20) NOT NULL,       -- e.g. 'HOBBIES'
    store_id  NVARCHAR(10) NOT NULL,       -- e.g. 'CA_1'
    state_id  NVARCHAR(5)  NOT NULL,       -- 'CA', 'TX', 'WI'
    d         NVARCHAR(10) NOT NULL,       -- 'd_1' .. 'd_1941' (join key to calendar.d)
    sales     INT          NOT NULL        -- units sold that day
)
WITH (DATA_COMPRESSION = PAGE);  -- ~50-70% disk savings on 59M-row table; major Free-tier win
GO
