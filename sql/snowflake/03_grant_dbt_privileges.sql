-- =============================================================================
-- 03_grant_dbt_privileges.sql
-- =============================================================================
-- Grants RETAIL_ENGINEER the additional privilege Phase 4 (dbt) needs:
-- CREATE SCHEMA at the database level. Phase 2 provisioning granted only
-- the privileges to operate inside RETAIL_DB.RAW — dbt needs to auto-create
-- STAGING / INTERMEDIATE / WAREHOUSE / MARTS at first run.
--
-- Snowflake's ownership model handles the rest: the role that creates a
-- schema owns it, with full privileges inside.
--
-- Idempotent (GRANT is naturally so). Run as ACCOUNTADMIN via Snowsight.
-- Phase: 4 — dbt transformations
-- =============================================================================


USE ROLE ACCOUNTADMIN;

GRANT CREATE SCHEMA ON DATABASE RETAIL_DB TO ROLE RETAIL_ENGINEER;

-- Verification — the new CREATE SCHEMA row should appear on DATABASE RETAIL_DB.
SHOW GRANTS TO ROLE RETAIL_ENGINEER;
