-- ============================================================================
-- 00_provision_account.sql
-- ============================================================================
-- Provisions the Snowflake objects needed for the retail demand forecasting
-- pipeline:
--     - Warehouse:  WH_RETAIL       (XS compute, auto-suspend, auto-resume)
--     - Database:   RETAIL_DB
--     - Schema:     RETAIL_DB.RAW   (landing zone for Azure SQL extract)
--     - Role:       RETAIL_ENGINEER (least-privilege project role)
--     - Grants:     warehouse + database + schema + future tables to role
--     - User grant: RETAIL_ENGINEER granted to user PHELUCIAM
--
-- Idempotent: uses CREATE ... IF NOT EXISTS throughout. Safe to re-run.
-- Run as ACCOUNTADMIN (default role on a fresh Snowflake trial).
--
-- Phase: 2 — Snowflake + extraction
-- Executed via: Snowsight worksheet (paste, Run All)
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 0. Role context — admin operations require ACCOUNTADMIN.
-- ----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;


-- ----------------------------------------------------------------------------
-- 1. Compute — warehouse
-- ----------------------------------------------------------------------------
-- XSMALL is the smallest (cheapest) size — 1 credit/hour while running.
-- AUTO_SUSPEND = 60 means the warehouse pauses after 60 seconds idle
-- (saves credits). AUTO_RESUME = TRUE means it wakes automatically on
-- the next query (1–2 sec resume time, transparent to queries).
-- INITIALLY_SUSPENDED = TRUE means it starts paused — no credit burn
-- until the first real query.
CREATE WAREHOUSE IF NOT EXISTS WH_RETAIL
    WITH WAREHOUSE_SIZE = 'XSMALL'
         AUTO_SUSPEND = 60
         AUTO_RESUME = TRUE
         INITIALLY_SUSPENDED = TRUE
         COMMENT = 'XS compute for the retail demand forecasting pipeline (M5 dataset)';


-- ----------------------------------------------------------------------------
-- 2. Storage — database + schema
-- ----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS RETAIL_DB
    COMMENT = 'Retail demand forecasting pipeline — Walmart M5 dataset';

CREATE SCHEMA IF NOT EXISTS RETAIL_DB.RAW
    COMMENT = 'Raw layer — landed direct from Azure SQL extract (no transformations)';


-- ----------------------------------------------------------------------------
-- 3. Role — least-privilege project role
-- ----------------------------------------------------------------------------
-- All day-to-day work (Python extract, dbt, Power BI connector) uses this
-- role — never ACCOUNTADMIN. Standard Snowflake security pattern.
CREATE ROLE IF NOT EXISTS RETAIL_ENGINEER
    COMMENT = 'Owns the retail demand forecasting pipeline objects';


-- ----------------------------------------------------------------------------
-- 4. Privileges — grant role access to the resources it needs
-- ----------------------------------------------------------------------------

-- Warehouse: USAGE = "can run queries on it". OPERATE = "can resume/suspend
-- the warehouse" (useful when a query wakes a paused warehouse).
GRANT USAGE   ON WAREHOUSE WH_RETAIL TO ROLE RETAIL_ENGINEER;
GRANT OPERATE ON WAREHOUSE WH_RETAIL TO ROLE RETAIL_ENGINEER;

-- Database: USAGE = "can see this database in metadata".
-- CREATE SCHEMA = "can create new schemas at the database level".
-- Required for dbt (Phase 4) to auto-create the STAGING / INTERMEDIATE /
-- WAREHOUSE / MARTS schemas. Added 2026-05-15 after Phase 4 session 2
-- caught the gap — see LEARNINGS.md "The grant-fix gap".
GRANT USAGE         ON DATABASE RETAIL_DB TO ROLE RETAIL_ENGINEER;
GRANT CREATE SCHEMA ON DATABASE RETAIL_DB TO ROLE RETAIL_ENGINEER;

-- Schema: USAGE = "can see objects in this schema".
-- CREATE TABLE / VIEW / STAGE / FILE FORMAT = "can build new objects here".
GRANT USAGE              ON SCHEMA RETAIL_DB.RAW TO ROLE RETAIL_ENGINEER;
GRANT CREATE TABLE       ON SCHEMA RETAIL_DB.RAW TO ROLE RETAIL_ENGINEER;
GRANT CREATE VIEW        ON SCHEMA RETAIL_DB.RAW TO ROLE RETAIL_ENGINEER;
GRANT CREATE STAGE       ON SCHEMA RETAIL_DB.RAW TO ROLE RETAIL_ENGINEER;
GRANT CREATE FILE FORMAT ON SCHEMA RETAIL_DB.RAW TO ROLE RETAIL_ENGINEER;

-- Existing tables (none yet, but harmless and future-proof) — full DML.
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES
    ON ALL TABLES IN SCHEMA RETAIL_DB.RAW
    TO ROLE RETAIL_ENGINEER;

-- Future tables — auto-grant DML to anything created later in this schema.
-- Critical: without this, every new table needs an explicit GRANT.
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES
    ON FUTURE TABLES IN SCHEMA RETAIL_DB.RAW
    TO ROLE RETAIL_ENGINEER;


-- ----------------------------------------------------------------------------
-- 5. Role hierarchy — let SYSADMIN also assume this role (best practice)
-- ----------------------------------------------------------------------------
-- Standard Snowflake pattern: grant project roles to SYSADMIN so the
-- system-admin role can also operate them when needed (without needing
-- ACCOUNTADMIN). Aligns with Snowflake's recommended role hierarchy.
GRANT ROLE RETAIL_ENGINEER TO ROLE SYSADMIN;


-- ----------------------------------------------------------------------------
-- 6. User grant — let PHELUCIAM assume this role
-- ----------------------------------------------------------------------------
GRANT ROLE RETAIL_ENGINEER TO USER PHELUCIAM;


-- ----------------------------------------------------------------------------
-- 7. Session timezone — Snowflake defaults to America/Los_Angeles on new
--    accounts. Override to Australia/Melbourne so all timestamps display
--    in local wall-clock time (Melbourne and Sydney share AEST/AEDT).
--    Affects audit columns like RAW.*.loaded_at and CURRENT_TIMESTAMP().
-- ----------------------------------------------------------------------------

-- Persistent: applies to every future session this user opens.
ALTER USER PHELUCIAM SET TIMEZONE = 'Australia/Melbourne';

-- Immediate: applies to the *current* session (so the verify SELECT
-- below renders in Melbourne time on a fresh run-through).
ALTER SESSION SET TIMEZONE = 'Australia/Melbourne';


-- ----------------------------------------------------------------------------
-- 8. Verify — switch into the new role and confirm everything is wired up
-- ----------------------------------------------------------------------------
USE ROLE      RETAIL_ENGINEER;
USE WAREHOUSE WH_RETAIL;
USE DATABASE  RETAIL_DB;
USE SCHEMA    RAW;

SELECT
    CURRENT_ROLE()      AS active_role,
    CURRENT_WAREHOUSE() AS active_warehouse,
    CURRENT_DATABASE()  AS active_database,
    CURRENT_SCHEMA()    AS active_schema,
    CURRENT_USER()      AS active_user,
    CURRENT_VERSION()   AS snowflake_version,
    CURRENT_TIMESTAMP() AS now_local;
