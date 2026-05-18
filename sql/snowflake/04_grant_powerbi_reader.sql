-- =============================================================================
-- 04_grant_powerbi_reader.sql
-- =============================================================================
-- Provisions POWERBI_READER, a least-privilege role for Power BI Desktop to
-- consume WAREHOUSE.fact_* + dim_* and MARTS.mart_* under read-only access.
-- Granted to user PHELUCIAM as a second role alongside RETAIL_ENGINEER (dbt).
--
-- Idempotent. Run as ACCOUNTADMIN via Snowsight. SHOW GRANTS at the end
-- proves only USAGE + SELECT — no write privileges anywhere.
--
-- See POWERBI_PIPELINE.md for the principle-of-least-privilege walkthrough.
-- Phase: 5 — Power BI + forecasting (session 1)
-- =============================================================================


USE ROLE ACCOUNTADMIN;


-- Role.
CREATE ROLE IF NOT EXISTS POWERBI_READER
    COMMENT = 'Read-only role for Power BI Desktop to consume WAREHOUSE + MARTS';


-- Compute. USAGE only — no OPERATE.
GRANT USAGE ON WAREHOUSE WH_RETAIL TO ROLE POWERBI_READER;


-- Database. USAGE only — no CREATE SCHEMA.
GRANT USAGE ON DATABASE RETAIL_DB TO ROLE POWERBI_READER;


-- WAREHOUSE schema — analyst-facing star (fact + conformed dims).
GRANT USAGE ON SCHEMA RETAIL_DB.WAREHOUSE TO ROLE POWERBI_READER;
GRANT SELECT ON ALL    TABLES IN SCHEMA RETAIL_DB.WAREHOUSE TO ROLE POWERBI_READER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RETAIL_DB.WAREHOUSE TO ROLE POWERBI_READER;
GRANT SELECT ON ALL    VIEWS  IN SCHEMA RETAIL_DB.WAREHOUSE TO ROLE POWERBI_READER;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA RETAIL_DB.WAREHOUSE TO ROLE POWERBI_READER;


-- MARTS schema — pre-aggregated rollups (Home page + Forecast vs Actual).
GRANT USAGE ON SCHEMA RETAIL_DB.MARTS TO ROLE POWERBI_READER;
GRANT SELECT ON ALL    TABLES IN SCHEMA RETAIL_DB.MARTS TO ROLE POWERBI_READER;
GRANT SELECT ON FUTURE TABLES IN SCHEMA RETAIL_DB.MARTS TO ROLE POWERBI_READER;
GRANT SELECT ON ALL    VIEWS  IN SCHEMA RETAIL_DB.MARTS TO ROLE POWERBI_READER;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA RETAIL_DB.MARTS TO ROLE POWERBI_READER;


-- Role hierarchy + user grant.
GRANT ROLE POWERBI_READER TO ROLE SYSADMIN;
GRANT ROLE POWERBI_READER TO USER PHELUCIAM;


-- Verify — switch into the new role and prove the boundary.
USE ROLE      POWERBI_READER;
USE WAREHOUSE WH_RETAIL;
USE DATABASE  RETAIL_DB;
USE SCHEMA    MARTS;

SELECT COUNT(*) AS mart_row_count FROM RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW;
SELECT COUNT(*) AS fact_row_count FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES;

SHOW GRANTS TO ROLE POWERBI_READER;


-- Negative boundary test — uncomment to prove POWERBI_READER cannot SELECT
-- from schemas it has no USAGE on (RAW / STAGING / INTERMEDIATE).
-- Expected outcome: "Object does not exist or not authorized."
-- SELECT COUNT(*) FROM RETAIL_DB.RAW.M5_SALES_TRAIN;
