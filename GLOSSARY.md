# Glossary of Terms — Retail Demand & Forecasting Pipeline

> A working vocabulary for this project and a carry-forward reference for future
> data engineering work. General terms (data engineering fundamentals, SQL,
> Python, Git) are written so they can be lifted straight into the next project.
> Project-specific entries are tagged `[Project 2]`.
>
> Built 2026-05-16. Extended as new terms come up.

---

## Table of contents

1. [Data Engineering Core](#1-data-engineering-core)
2. [Dimensional Modelling](#2-dimensional-modelling)
3. [SQL & Database Concepts](#3-sql--database-concepts)
4. [Snowflake](#4-snowflake)
5. [dbt](#5-dbt)
6. [Airflow & Orchestration](#6-airflow--orchestration)
7. [Azure SQL & Cloud Concepts](#7-azure-sql--cloud-concepts)
8. [Python Ecosystem](#8-python-ecosystem)
9. [Git & GitHub](#9-git--github)
10. [PowerShell & Shell Basics](#10-powershell--shell-basics)
11. [Power BI & BI Concepts](#11-power-bi--bi-concepts)
12. [Testing & QA](#12-testing--qa)
13. [CI/CD & DevOps](#13-cicd--devops)
14. [Security & IAM](#14-security--iam)
15. [Project-Specific Terms](#15-project-specific-terms-project-2)
16. [Acronyms Quick Reference](#16-acronyms-quick-reference)

---

## 1. Data Engineering Core

### **ETL** (Extract, Transform, Load)

The classic pipeline shape: pull data from a source, reshape it on the way, write the reshaped result into the destination. Transformation happens _before_ the data lands in the warehouse — usually on a dedicated server or in the extract script itself.

**Why it matters:** Still the right pattern when the destination is expensive (limited compute) or strict about what it accepts. Useful as the conceptual contrast to ELT.

### **ELT** (Extract, Load, Transform)

The modern variation: pull data from the source, dump it into the warehouse _as-is_ (the RAW layer), then transform inside the warehouse using SQL. Cheap, elastic warehouse compute makes this practical where ETL was historically necessary.

**In this project:** Pure ELT. The Airflow-scheduled Python extract does almost no transformation — it just copies Azure SQL rows into `RETAIL_DB.RAW`. All reshaping, joins, business logic and the [star schema](#star-schema) live in [dbt](#dbt) running against Snowflake.

**Why it matters:** ELT is the default for the modern data stack. Knowing the difference between ETL and ELT — and being able to justify ELT to someone whose mental model still says "transform before you land" — is table stakes.

### **OLTP** (Online Transaction Processing)

A database optimised for many small, concurrent writes and point lookups — the "system of record" behind an app, an ERP, or a checkout till. Rows are typically narrow, indexes are heavy, schemas are normalised.

**In this project:** Azure SQL Database plays the OLTP role, simulating an ERP or Microsoft Dynamics back-end. M5 data lives there before being extracted.

### **OLAP** (Online Analytical Processing)

A database optimised for large analytical reads across many rows — `SELECT SUM(...) GROUP BY ...` over millions of rows. Wider denormalised tables, columnar storage, no row-level locking concerns.

**In this project:** Snowflake plays the OLAP role. The [star schema](#star-schema) and [marts](#mart) live there.

**Why it matters:** OLTP and OLAP have opposite optimisation targets. Using one for the other's workload is the single most common architecture mistake. Power BI directly on top of an OLTP system is what this project is explicitly _not_ doing.

### **Batch processing**

Data is moved or transformed on a fixed cadence (hourly, daily, monthly) rather than the instant it arrives. The unit of work is a chunk — yesterday's sales, last hour's events — not a single row.

**In this project:** The whole pipeline is batch. Airflow's `@daily` schedule fires the extract once per simulated day.

### **Streaming**

The opposite of batch: events flow through the pipeline continuously, processed individually or in micro-windows. Kafka, Kinesis, Pub/Sub are the usual transports.

**Why it matters:** Worth knowing exists, but batch is still the right default for most analytics work. Streaming pays off when latency matters (fraud detection, real-time dashboards) and adds operational cost when it doesn't.

### **Warehouse** (data warehouse)

A central analytical database holding cleaned, modelled data ready for reporting. Schemas are designed for query speed and analyst comprehension, not transactional writes. Snowflake, BigQuery, Redshift, Synapse are warehouses.

**In this project:** Snowflake `RETAIL_DB` is the warehouse, with layered schemas RAW → STAGING → INTERMEDIATE → WAREHOUSE → MARTS.

### **Lakehouse**

A pattern that puts a warehouse-style query engine on top of files in cheap object storage (S3, ADLS, GCS). Same SQL surface as a warehouse; the storage layer is open file formats (Parquet, Delta, Iceberg) you can also reach from Spark, Trino, or DuckDB.

**Why it matters:** The likely Project 3 architecture. Deliberately out of scope here — this project keeps the simpler warehouse-only shape.

### **Medallion architecture** (bronze / silver / gold)

Databricks' branded version of layered data refinement: bronze (raw landing), silver (cleaned, conformed), gold (business-ready, aggregated). Conceptually identical to dbt's [staging / intermediate / warehouse / marts](#layered-architecture-staging--intermediate--warehouse--marts) flow.

**Why it matters:** Same idea, different vocabulary. Recognising that "medallion" and "the dbt four-layer pattern" are siblings, not rivals, saves confusion in interviews.

### **Idempotency**

Property of an operation that can be run repeatedly without changing the result beyond the first run. In data pipelines: re-running a script after a partial failure should leave the destination in the same state as a clean first run — no duplicates, no orphaned partial rows.

**In this project:** `extract_azure_to_snowflake.py` is idempotent by design — re-running for the same date window `DELETE`s the target slice before re-loading, so a mid-run crash + restart produces identical output to a clean single run. `CODE_QUALITY.md` lists idempotency as failsafe #8.

**Why it matters:** Pipelines that aren't idempotent become operationally expensive — every failure requires manual reconciliation. Idempotency is the difference between "page someone at 3am" and "the retry handled it."

### **Backfill**

Loading historical data into a pipeline that was built after the data already existed. Distinct from incremental processing: backfill is the one-time "catch up to now" event; incremental is the steady-state "one new slice per run."

**In this project:** Phase 2 session 3 ran a 3-year backfill (2011-01-29 → 2013-12-31) in a single 27-minute extract. Phases 3+ run incremental, one M5 day per Airflow tick.

### **Freshness**

How recently the data in the destination was updated, measured against an audit column or `last_modified` field. Stale data is silently dangerous — dashboards still render, just with last week's numbers.

**In this project:** Every RAW Snowflake table has a `loaded_at` column. [dbt's `dbt source freshness`](#dbt-source-freshness) command checks `MAX(loaded_at)` against 36h/72h warn/error thresholds declared in `sources.yml`.

### **CDC** (Change Data Capture)

A pattern for capturing row-level changes from a source database as they happen — typically by reading the database's transaction log — and replaying them into the destination. Avoids full re-extracts and captures deletes that simple timestamp polling misses.

**Why it matters:** The "right" answer for many production extract problems. Out of scope here (Project 2 uses simpler date-windowed polling), but expected vocabulary for a DE.

### **Pipeline**

End-to-end chain of steps that moves data from source to consumer. In this project: Kaggle CSV → Azure SQL → Airflow-driven Python extract → Snowflake RAW → dbt → Snowflake STAGING/INTERMEDIATE/WAREHOUSE/MARTS → Power BI.

### **Orchestration**

Coordinating _when_ and _in what order_ the pieces of a pipeline run. The orchestrator decides which task can start (its upstream dependencies are met), retries failures, handles schedules, and surfaces errors.

**In this project:** Apache Airflow plays this role. Without it the extract is just a Python script someone has to remember to run.

### **Layered architecture (staging / intermediate / warehouse / marts)**

A discipline of splitting transformations into named layers, each with a single job: staging cleans, intermediate joins business logic, warehouse builds the [star schema](#star-schema), marts pre-aggregate for BI. Same data flows top-to-bottom; nothing skips a layer.

**In this project:** Four [dbt](#dbt) schemas under `RETAIL_DB`, one Snowflake schema per layer. Documented in `DBT_PIPELINE.md`.

**Why it matters:** Single-script "do everything" SQL is the BI-analyst trap. Layering trades a bit of typing for a lot of debuggability — when something goes wrong you know exactly which layer to look in.

### **Data contract**

The agreed shape of data flowing between two systems — column names, types, NULL conventions, row counts, encoding. Breaking a contract upstream causes silent corruption downstream; the discipline is making the contract explicit so a break shows up as a test failure, not a confusing dashboard.

**In this project:** `CODE_QUALITY.md` criterion 7 is "Upstream/downstream contract." `extract_azure_to_snowflake.py` verifies source vs destination row counts on every run.

---

## 2. Dimensional Modelling

### **Kimball methodology**

The dominant approach to designing analytical schemas — Ralph Kimball's "build a [star schema](#star-schema) per business process, with [conformed dimensions](#conformed-dimension) shared between them." Bottom-up: build the marts users actually need, not a top-down enterprise data model.

**In this project:** The warehouse layer is pure Kimball — fact and dim tables, surrogate keys, conformed dimensions.

### **Inmon methodology**

The contrast to Kimball — Bill Inmon's "build a normalised enterprise data warehouse first, then derive data marts from it." Top-down, slower to first value, but more consistent at scale across very large organisations.

**Why it matters:** Real production environments are usually Kimball flavours; knowing the Inmon-vs-Kimball distinction is interview vocabulary, not day-to-day work.

### **Star schema**

A dimensional model with one [fact table](#fact-table) in the middle and several [dimension tables](#dimension-table) around it, joined by surrogate keys. Looks like a star when you draw it. The shape that BI tools (Power BI, Tableau) are designed to consume.

**In this project:** `fact_daily_sales` in the centre, joined to `dim_item`, `dim_store`, `dim_calendar`.

### **Snowflake schema** (the data modelling pattern)

A star schema where dimension tables are themselves normalised into sub-dimensions (e.g. `dim_item` → `dim_product_family` → `dim_department`). Saves a tiny bit of storage at the cost of more joins and slower queries. Almost always the wrong choice in modern columnar warehouses.

**Why it matters:** Easy to confuse with the _vendor_ [Snowflake](#snowflake). Different things; the cloud warehouse is named after the schema shape but doesn't require it.

### **Fact table**

The big table at the centre of a [star schema](#star-schema). Contains the numeric measurements of a business process (sales, transactions, page views) along with foreign keys to dimension tables. Many rows, narrow shape.

**In this project:** `fact_daily_sales` — one row per (store, item, day) at ~58M rows. Partitioned on `sale_date`, built incrementally.

### **Dimension table** (dim)

The descriptive lookup tables surrounding a [fact table](#fact-table). Hold the "who / what / where / when" attributes that get used as filters and labels in reports.

**In this project:** `dim_item` (SKU attributes), `dim_store` (store and state), `dim_calendar` (date and fiscal-week features).

### **Grain**

The level of detail of a single row in a fact table — the answer to "what does one row mean?" Defining grain first is the single most important decision in dimensional modelling.

**In this project:** `fact_daily_sales` grain is **one row per store per item per day**. Every analytical question has to roll up from there.

### **Surrogate key**

A meaningless integer or hash assigned by the warehouse, used purely to join fact to dim. Insulates the model from changes in source keys, simplifies SCD Type 2, and gives a clean integer to index on.

**In this project:** Every dim has a `<entity>_key` column generated with [dbt_utils.generate_surrogate_key](#dbt_utilsgenerate_surrogate_key). Naming convention locked in `PROJECT_PLAN.md`.

### **Natural key** (business key)

The identifier that exists in the source system — `item_id`, `store_id`, customer email. Has business meaning; can change over time, can be reused, can collide across systems.

**In this project:** Stored as `<entity>_id` alongside the [surrogate key](#surrogate-key). Both kept in dim tables — surrogate for joins, natural for human readability and source-system lookups.

### **Slowly Changing Dimension** (SCD)

A pattern for tracking how a dimension's attributes change over time. **Type 1** overwrites — only the current value is kept. **Type 2** keeps history with `valid_from` / `valid_to` columns plus a new surrogate key per change. **Type 3** keeps one previous value in a separate column. Type 2 is what people usually mean when they say "SCD."

**Why it matters:** Real businesses change — stores get rebranded, products get re-categorised. SCD Type 2 is how the warehouse remembers what the world looked like at the time of each transaction. dbt has snapshots for this. Out of scope for Project 2; expected for Project 3.

### **Conformed dimension**

A dimension used identically across multiple fact tables — `dim_calendar` joined to sales, inventory, and forecasts all by the same `date_key`. Conformance is what makes cross-process analysis possible without translation tables.

### **Role-playing dimension**

One physical dimension table referenced multiple times with different aliases — `dim_calendar` joined once as "order_date" and again as "ship_date". Saves duplicating the dim.

### **Star vs snowflake (schema) trade-off**

Star = denormalised dims, fewer joins, faster reads, more storage. Snowflake-schema = normalised dims, more joins, smaller storage, slower reads. In a columnar warehouse the storage saving is negligible and the extra joins aren't free — go star.

---

## 3. SQL & Database Concepts

### **DDL** (Data Definition Language)

The subset of SQL that creates and modifies database objects — `CREATE TABLE`, `ALTER TABLE`, `DROP TABLE`, `CREATE VIEW`. Distinct from [DML](#dml-data-manipulation-language) (which moves rows).

**In this project:** `sql/snowflake/01_create_raw_tables.sql` is pure DDL — defines the three RAW tables.

### **DML** (Data Manipulation Language)

The subset of SQL that moves rows around — `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `MERGE`. Where the day-to-day analyst work happens.

### **CTE** (Common Table Expression)

A named, temporary result set inside a SQL query, declared with `WITH ... AS (...)`. Lets you break a complex query into readable, debuggable steps that flow top-to-bottom instead of nesting subqueries inside-out. In most warehouses CTEs are evaluated once and reused — they're a structuring tool, not a performance lever.

**In this project:** `stg_m5_sales_train.sql` uses a CTE chain (source → calendar → joined) so each step can be debugged by swapping which CTE the final `SELECT` reads from. Standard dbt staging pattern. Also the shape of the PASS/FAIL verification template in `sql/verify/03_phase3_dag_extract_verification.sql`.

**Why it matters:** Real production SQL is dominated by CTEs. Reading one fluently is table stakes; writing them well is a senior signal.

### **MERGE** (UPSERT)

A single SQL statement that inserts new rows and updates existing ones in one pass, keyed by some match condition. Avoids the race condition of "SELECT first, then INSERT or UPDATE."

**Why it matters:** Underpins most incremental warehouse patterns including dbt's `incremental` materialization with `unique_key` set.

### **UPSERT**

Shorthand for "update if it exists, insert if it doesn't" — the operation [MERGE](#merge-upsert) implements. Not a SQL keyword in Snowflake or T-SQL but appears in PostgreSQL as `INSERT ... ON CONFLICT ... DO UPDATE`.

### **NULL semantics**

NULL is "unknown," not "empty" or "zero." `NULL = NULL` evaluates to NULL (not TRUE) — you need `IS NULL`. Aggregations skip NULLs by default. `JOIN` keys with NULL on either side don't match. Most production bugs trace back to forgetting one of these rules.

**In this project:** The [LEFT-JOIN-as-sentinel pattern](#left-join-as-sentinel-pattern) in `stg_m5_sales_train` deliberately produces NULL `sale_date` rows when the calendar join misses, then a `NOT NULL` test catches the NULL as a failure.

### **JOIN types**

- **INNER** — only rows matching in both sides survive.
- **LEFT** — every row on the left survives; right side is NULL where no match.
- **RIGHT** — mirror of LEFT.
- **FULL OUTER** — every row from both sides survives; NULLs on whichever side missed.
- **CROSS** — Cartesian product; every left row paired with every right row.

**Why it matters:** Choosing the wrong join is the second-most-common SQL bug after [NULL semantics](#null-semantics). The conventional discipline is "default to LEFT JOIN with a `NOT NULL` sentinel test rather than INNER JOIN that silently drops rows."

### **Index**

A separate sorted data structure that lets the database find rows by a key without scanning the whole table. Speeds reads, slows writes (each insert maintains the index). Columnar warehouses like Snowflake don't have classical indexes — they use [micro-partitions](#micro-partition) and [clustering keys](#clustering-key) instead.

**In this project:** No indexes on Azure SQL raw tables — bulk load is faster without them, and the heavy query work happens downstream in Snowflake.

### **Partitioning**

Splitting a table into physical sub-units, typically by date or another high-cardinality column. Queries that filter on the partition key only read the relevant partitions — huge speedup on large tables.

**In this project:** `fact_daily_sales` will be partitioned on `sale_date` (Snowflake auto-partitions via [micro-partitions](#micro-partition) but clustering on `sale_date` reinforces it).

### **Clustering** (clustering key)

Sorting / co-locating data within partitions by some column so range scans hit fewer files. The Snowflake equivalent of "tell the optimiser which column you usually filter on."

**In this project:** `fact_daily_sales` clusters on `sale_date`. Considered clustering RAW `sales_train` on `d` but skipped — see [LEARNINGS.md / Snowflake / Clustering keys when NOT to cluster].

### **Transaction**

A unit of work that either fully succeeds or fully fails — no partial state. Database operations inside `BEGIN ... COMMIT` are atomic. ACID (Atomicity, Consistency, Isolation, Durability) is the formal guarantee.

### **Isolation level**

How strictly concurrent transactions are kept from interfering with each other. From least strict to most: READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE. Tighter isolation = fewer race conditions = lower concurrency. Snowflake uses SNAPSHOT isolation by default.

**Why it matters:** Mostly an [OLTP](#oltp-online-transaction-processing) concern; an analytical warehouse rarely lets the analyst pick. Worth knowing the vocabulary because interview questions still ask.

### **T-SQL**

Microsoft's dialect of SQL used in SQL Server and Azure SQL Database. Adds procedural extensions (`BEGIN ... END`, `WHILE`, variable declarations) on top of standard SQL.

**In this project:** Azure SQL queries in `scripts/extract_azure_to_snowflake.py` are T-SQL; Snowflake-side queries are standard SQL with Snowflake extensions.

### **DAG (graph sense)**

In computer-science terms, a **D**irected **A**cyclic **G**raph — nodes connected by one-way edges with no cycles allowed. The "no cycles" constraint is what makes it possible to compute a topological order: which step has to run before which.

**In this project:** dbt builds a DAG of models from `ref()` calls — if model A references model B, B has to run first. `dbt run --select +my_model` says "this model plus everything upstream of it in the DAG."

### **Topological order**

The output of a DAG sort — an ordering of nodes where every dependency comes before its dependents. dbt and Airflow both produce one internally so they know what to run next.

---

## 4. Snowflake

### **Snowflake** (the warehouse)

Cloud-native columnar data warehouse running on AWS, Azure, or GCP. Distinguishing features: separation of storage from compute (you can scale them independently), zero-copy cloning, auto-suspending virtual warehouses, no infrastructure management.

**In this project:** Account `ghrcrqs-hw63290` on AWS `ap-southeast-2` (Sydney). Free trial.

### **Account identifier**

The unique handle for a Snowflake account, used in the connection URL (`<account>.snowflakecomputing.com`). Looks like `ghrcrqs-hw63290` — region-specific, cloud-specific.

**In this project:** Set via `SNOWFLAKE_ACCOUNT` in `.env`, consumed by both the Python connector and dbt's `profiles.yml`.

### **Virtual warehouse** (compute)

In Snowflake terminology, a "warehouse" is the **compute cluster** — not the database. A virtual warehouse is a sized group of cloud VMs that executes your queries. Suspended warehouses cost nothing; running ones bill by the second.

**In this project:** `WH_RETAIL`, sized X-SMALL, auto-suspend 60s, auto-resume on next query. Wakes in 1-2 seconds.

### **Database** (Snowflake)

A logical container of [schemas](#schema-snowflake) inside a Snowflake account. Multiple databases per account is normal.

**In this project:** `RETAIL_DB` holds every schema for the project (RAW, STAGING, INTERMEDIATE, WAREHOUSE, MARTS).

### **Schema** (Snowflake)

A namespace inside a [database](#database-snowflake) that holds tables, views, and other objects. Same word as [profile schema](#profile-schema-vs-folder-schema-in-dbt) in dbt's profiles — context matters.

**In this project:** Five schemas per layer, matching the dbt layer-by-layer materialization strategy.

### **Role** (RBAC role)

A bag of privileges that a user can assume. Snowflake's authorisation model is role-based — privileges are never granted directly to users, only to roles, which are then granted to users.

**In this project:** `RETAIL_ENGINEER` is the project role. ACCOUNTADMIN was used only for one-time provisioning; all real work runs as RETAIL_ENGINEER.

### **Role hierarchy**

Roles can be granted to other roles, forming a tree. A user assuming the parent role inherits everything the child role can do. Standard pattern: `RETAIL_ENGINEER → SYSADMIN → ACCOUNTADMIN`.

### **Ownership model**

In Snowflake, the role that creates an object owns it and has full privileges on it automatically. When `RETAIL_ENGINEER` runs `CREATE SCHEMA STAGING`, it owns the new schema — no need for follow-up grants.

**In this project:** Caught a permission gap mid-Phase-4: `RETAIL_ENGINEER` had everything inside `RAW` but couldn't `CREATE SCHEMA` at the database level. One grant fixed it cleanly; ownership model handled the rest.

### **`COPY INTO`**

Snowflake's bulk-load SQL command. Reads files from a stage (internal or external — S3, ADLS, GCS) into a target table, in parallel, using Snowflake's own loader. The fastest way to get data into Snowflake.

**In this project:** Used under the hood by [`write_pandas`](#write_pandas) — the function PUTs a Parquet file to an internal stage then issues `COPY INTO`. The user just calls one Python function.

### **Stage** (Snowflake)

A location Snowflake can read files from for loading. **Internal stages** are inside the account (managed by Snowflake); **external stages** are S3/ADLS/GCS buckets pointed to by URL + credentials.

### **Micro-partition**

Snowflake's internal storage unit — immutable compressed columnar files of ~50–500 MB. Replaces the concept of indexes from row-store databases. Snowflake's optimiser uses micro-partition metadata (min/max per column) to skip files that can't contain the query's rows.

### **`AUTO_SUSPEND` / `AUTO_RESUME`**

Warehouse settings. `AUTO_SUSPEND = 60` puts the warehouse to sleep after 60 seconds of inactivity (no credit burn). `AUTO_RESUME = TRUE` wakes it on the next query, transparently. Together they make near-zero-idle-cost a one-line config.

### **X-SMALL** (XS)

The smallest virtual warehouse size — 1 credit per running hour, 1 server. Plenty for a portfolio project. Sizes go XS, S, M, L, XL, 2XL, 3XL, 4XL — each step doubles cost and (approximately) throughput.

### **`TIMESTAMP_NTZ` / `TIMESTAMP_LTZ` / `TIMESTAMP_TZ`**

Three Snowflake timestamp variants. NTZ = "No Time Zone" (wall clock only, no offset stored — NOT New Zealand). LTZ = "Local Time Zone" (stored as UTC, displayed in the session's timezone). TZ = explicit offset stored with each value.

**In this project:** RAW tables use `loaded_at TIMESTAMP_NTZ(9)` — the `(9)` is nanosecond precision.

### **Snowsight**

Snowflake's web UI for running SQL, managing objects, and viewing query history. The "worksheet" tabs are where SQL actually executes — disk files are source-of-truth; Snowsight is where they're pasted and run.

---

## 5. dbt

### **dbt** (data build tool)

Open-source SQL templating + orchestration tool that turns folders of `.sql` files into a built data model in your warehouse. dbt itself does no data processing — it sends SQL to the warehouse over HTTPS and the warehouse does the work. Your laptop runs dbt; Snowflake (or BigQuery, Redshift, Postgres) runs the SQL.

**In this project:** `dbt-snowflake 1.11.5` installed into the project venv. Manages STAGING / INTERMEDIATE / WAREHOUSE / MARTS layers against `RETAIL_DB`.

### **Model**

A `.sql` file in `dbt/models/` containing a single `SELECT` statement. dbt wraps the SELECT in a `CREATE OR REPLACE VIEW/TABLE ... AS ...` statement and runs it. The model's name is the file name.

**In this project:** `stg_m5_calendar.sql`, `stg_m5_sell_prices.sql`, `stg_m5_sales_train.sql` are the first three. Materializes to `RETAIL_DB.STAGING.STG_M5_CALENDAR` etc.

### **Source** (dbt source)

A reference to a table dbt does _not_ manage — usually the RAW layer loaded by an upstream tool. Declared in `sources.yml`; referenced in models via `{{ source('m5', 'CALENDAR') }}`.

**In this project:** Three sources under the `m5` source name — CALENDAR, SELL_PRICES, SALES_TRAIN. All declared in `dbt/models/staging/sources.yml`.

### **`ref()`**

Jinja function: `{{ ref('my_other_model') }}` resolves to the fully-qualified name of another dbt model. The function call also tells dbt "this model depends on that one" — which is how dbt builds its DAG.

**In this project:** `stg_m5_sales_train` references `stg_m5_calendar` via `{{ ref('stg_m5_calendar') }}` — dbt automatically schedules calendar to build first.

### **`source()`**

Jinja function: `{{ source('source_name', 'table_name') }}` resolves to the fully-qualified name of a raw table declared in `sources.yml`. Same role as [ref()](#ref) but for tables dbt doesn't materialize.

### **Materialization**

How a model is physically built in the warehouse. dbt's built-in options:

- **view** — `CREATE OR REPLACE VIEW` — re-evaluates upstream on every query. Cheap, always fresh. Default for staging/intermediate.
- **table** — `CREATE OR REPLACE TABLE AS SELECT` — full rebuild on every `dbt run`. Fast reads, costs storage + rebuild compute.
- **incremental** — first run is a full table build; subsequent runs `MERGE` only new rows (defined by a `is_incremental()` filter inside the model). Used for big facts where full rebuild is too slow.
- **ephemeral** — never materialized; inlined as a CTE in any model that references it. Rare.

**In this project:** Staging and intermediate are `view`. Warehouse dims are `table`. `fact_daily_sales` will be `incremental`. Marts are `table`.

**Analogy:** Like a kitchen. A view is "I'll make it fresh when you order." A table is "I cooked a tray this morning, just take a slice." Incremental is "I cooked the tray once and top it up daily."

### **Jinja**

The templating language dbt uses to add Python-like logic to SQL — `{{ ... }}` for expressions, `{% ... %}` for control flow. Lets you do things SQL can't, like loop over a list of columns or conditionally include a clause.

**In this project:** Every `ref()`, `source()`, `env_var()` call is Jinja. The `generate_schema_name` macro is ~8 lines of Jinja.

**Why it matters:** New for Phil (flagged shaky in `TEACHING_PREFERENCES.md`). Worth investing in — most dbt mid-to-senior leverage comes from Jinja macros and `dbt_utils`.

### **`dbt_project.yml`**

The master dbt config file at the dbt project root. Defines the project name, points to a profile, sets folder paths, and configures per-layer defaults (materializations, schema names, tags). Says **what** dbt should do.

**In this project:** `dbt/dbt_project.yml`, ~35 lines. Full walkthrough in `DBT_PIPELINE.md`.

### **`profiles.yml`**

The dbt connection-details file. Says **where** dbt should connect — account, user, password, warehouse, database, schema. Conventionally lives at `~/.dbt/profiles.yml` but can live in the project directory.

**In this project:** Lives at `dbt/profiles.yml` (deliberately, for portfolio visibility), with every credential pulled from environment variables via [env_var()](#env_var). Safe to commit.

### **`env_var()`**

Jinja function inside `profiles.yml` (and other dbt files): `{{ env_var('SNOWFLAKE_PASSWORD') }}` reads the value from the shell environment at runtime. Keeps secrets out of YAML.

### **Profile schema vs folder schema (in dbt)**

`profiles.yml`'s `schema:` setting is the _default_ schema for the project. `dbt_project.yml`'s per-folder `+schema:` setting is an _override_ per layer. By default dbt **concatenates** them — profile `RAW` + folder `STAGING` = `RAW_STAGING` (ugly). The `generate_schema_name` macro overrides that to use the folder setting directly.

**In this project:** `dbt/macros/generate_schema_name.sql` — 8 lines of Jinja. Models land in clean `STAGING`, `INTERMEDIATE`, `WAREHOUSE`, `MARTS` schemas.

### **Target**

A named connection profile inside `profiles.yml`. Most projects have `dev` and `prod` targets with different credentials and a different default schema. Switch with `dbt run --target prod`.

**In this project:** One target — `dev`. Production would add `prod`.

### **`packages.yml`**

The dbt equivalent of `requirements.txt` — lists third-party dbt packages the project depends on. `dbt deps` reads it and installs the packages into `dbt_packages/`. Analogous to npm's `node_modules`.

### **`dbt_utils`**

The most-used dbt package, maintained by dbt Labs. Adds dozens of generic tests, macros, and SQL helpers — `generate_surrogate_key`, `unique_combination_of_columns`, `date_spine`, `pivot`. Essentially the "standard library" most production dbt projects depend on.

### **`dbt_utils.generate_surrogate_key`**

A macro that takes a list of columns and returns an MD5 hash of their concatenation. Used to generate [surrogate keys](#surrogate-key) deterministically — same input columns always produce the same hash.

**In this project:** Will be used on every dim to produce `<entity>_key` columns. Carry-forward discipline from Project 1 — never manual `||` concatenation.

### **Materializations (continued)** — see [materialization](#materialization).

### **Generic test**

A reusable dbt test that can be applied to any column by name. Built-in: `unique`, `not_null`, `accepted_values`, `relationships`. Declared in a model's schema YAML under `data_tests:`.

**In this project:** 14 generic tests on the three staging models — see the table in `DBT_PIPELINE.md`.

### **Singular test**

A standalone `.sql` file in `tests/` that returns rows. dbt passes the test if zero rows come back; any row returned counts as a failure. Used for ad-hoc business-rule checks too specific to be generic.

### **`schema.yml`** (or model YAML)

A YAML file alongside models that documents columns and declares tests. Conventionally named `_<folder>__models.yml` so it sorts to the top of the folder in a file listing.

**In this project:** `dbt/models/staging/_staging__models.yml` documents the three staging models plus 14 tests.

### **`sources.yml`**

A schema YAML that declares external [sources](#source-dbt-source). Holds source-table metadata, column docs, and [freshness](#freshness) thresholds. Conventionally one per layer / source group.

### **`dbt source freshness`**

CLI command that queries `MAX(loaded_at_field)` against each declared source and compares the age to the warn/error thresholds in `sources.yml`. Surfaces stale upstream data before downstream models run on it.

### **`dbt build`**

CLI command that runs every model and every test in dependency order, stopping at the first failure for each branch of the DAG. The "one command to rule them all" — preferred over running `dbt run` and `dbt test` separately because it interleaves them.

**In this project:** `dbt build --select staging` at the end of Phase 4 session 2 returned `PASS=17 WARN=0 ERROR=0` — 3 views plus 14 tests, ~5 seconds.

### **`dbt run` vs `dbt test` vs `dbt build`**

`dbt run` builds models, nothing else. `dbt test` runs tests against existing models, doesn't build anything. `dbt build` does both, in DAG order. For day-to-day development, `dbt build --select <something>` is the default.

### **`dbt debug`**

CLI command that checks dbt can reach the warehouse — credentials valid, warehouse reachable, default database/schema exist. Doesn't materialize anything. The first thing to run after editing `profiles.yml`.

**In this project:** Passed end-to-end at the close of Phase 4 session 1 — `Connection test: [OK connection ok]`, `All checks passed!`.

### **`dbt deps`**

CLI command that reads `packages.yml` and installs declared packages into `dbt_packages/`. Run after editing `packages.yml`.

### **`dbt parse`**

CLI command that parses every project file into the [manifest](#manifest) without connecting to the warehouse. Used in CI to validate that the project compiles before doing anything expensive.

### **`dbt docs generate`**

CLI command that produces a static HTML site with model documentation, lineage graph, and source freshness — fed by the schema YAMLs and source declarations. Can be hosted on GitHub Pages.

### **Manifest**

The compiled internal representation of a dbt project — every model, source, test, macro, and the DAG between them. Lives at `target/manifest.json` after any dbt command. Tools like dbt-osmosis and dbt-checkpoint read it.

### **Partial parse**

dbt caches the manifest and only re-parses changed files on subsequent runs. Speeds up `dbt run` from "tens of seconds" to "near-instant" on a project of a few dozen models.

### **`dbt_packages/`**

The folder dbt installs third-party packages into after `dbt deps`. Analogous to npm's `node_modules` or Python's `site-packages`. Gitignored.

### **Staging model** (`stg_*`)

The first dbt layer. One model per source table; renames columns, casts types, drops audit columns. **No joins, no business logic** (with rare exceptions like the `d_NNNN` → DATE translation in this project). Insulates downstream models from source-side changes.

### **Intermediate model** (`int_*`)

The second dbt layer. Joins across staging tables to assemble business concepts. Usually materialized as views.

### **Warehouse model** (`fact_*`, `dim_*`)

The dimensional-modelling layer — the Kimball [star schema](#star-schema) lives here. Surrogate keys, facts, dims, partitioned/incremental fact builds.

### **Mart model** (`mart_*`)

The final dbt layer. Pre-aggregated and flattened so the BI tool's query engine stays fast. Convention in this project: one mart per Power BI page.

### **LEFT-JOIN-as-sentinel pattern**

A defensive practice — use LEFT JOIN even when you "know" both sides should match, then add a `NOT NULL` test on a column from the right side. If a row ever fails to match, the test catches it as a failure instead of the row silently disappearing (which INNER JOIN would do).

**In this project:** `stg_m5_sales_train` LEFT JOINs `stg_m5_calendar` on `d`, then tests `sale_date NOT NULL`. First explicit use is the staging layer; will be reused on every join going forward.

---

## 6. Airflow & Orchestration

### **Apache Airflow**

Open-source workflow orchestrator. Pipelines are expressed as Python files (DAGs) that define tasks and their dependencies; the Airflow scheduler runs them on a schedule, handles retries, and surfaces failures in a web UI.

**In this project:** Airflow 2.10.3 in Docker, LocalExecutor, runs the `m5_daily_extract` DAG.

### **DAG (Airflow sense)**

In Airflow vocabulary, a "DAG" is the _whole pipeline_ — a Python file that defines a sequence of tasks with dependencies between them. Confusingly, it's also a [DAG (graph sense)](#dag-graph-sense) internally, but Airflow users say "DAG" to mean "the pipeline."

**In this project:** `m5_daily_extract.py` is a DAG containing two tasks — `extract_one_day` and `verify_one_day`.

**Why it matters:** When someone says "the DAG failed," they mean the pipeline run, not the graph data structure. Both meanings of DAG come up in the same sentence often.

### **Task**

The unit of work inside an [Airflow DAG](#dag-airflow-sense) — typically one Python function or shell command. Tasks have dependencies (`a >> b` means "run a before b"), retry policies, and timeouts.

**In this project:** Two tasks in the DAG — `extract_one_day` (calls the Python extract script) and `verify_one_day` (queries Snowflake to confirm rows landed).

### **Operator**

The Airflow class that defines _how_ a task runs — `PythonOperator`, `BashOperator`, `SnowflakeOperator`, etc. In the [TaskFlow API](#taskflow-api), operators are mostly invisible — decorators wrap them.

### **TaskFlow API**

Airflow's modern (2.0+) decorator-based syntax for writing DAGs. `@dag` on the DAG function, `@task` on each task function. Massively cleaner than the old `PythonOperator(...)` style — Python functions become tasks; their return values flow as inputs to downstream tasks.

**In this project:** `m5_daily_extract.py` uses `@dag` and `@task` exclusively.

### **Scheduler**

The Airflow process that parses DAG files, computes which task can run next, and submits tasks to the executor. The brain.

### **Executor**

The Airflow process that actually runs tasks. Options include:

- **LocalExecutor** — runs each task as a subprocess on the scheduler container. Single-machine; fine for portfolio projects and small production loads.
- **CeleryExecutor** — distributes tasks across worker processes using Redis or RabbitMQ as the broker. Horizontally scalable; standard production choice.
- **KubernetesExecutor** — launches a Kubernetes pod per task. Maximum isolation; cloud-native production.

**In this project:** LocalExecutor. Upgrade path to CeleryExecutor is "swap executor + add Redis broker + N workers" — same DAG code.

### **Webserver**

The Airflow process that serves the web UI at `localhost:8080`. Where you trigger DAGs, view logs, pause/unpause, and inspect run history.

### **Metadata database**

The Postgres (or MySQL) database Airflow uses internally to store DAG definitions, task states, run history, and config. Distinct from the data your pipeline moves.

**In this project:** A `postgres` container in the docker-compose stack. Holds Airflow's own state — nothing about M5 lives there.

### **Schedule**

How often a DAG should run. Common values: `@daily`, `@hourly`, `0 6 * * *` (cron syntax), or `None` (manual only).

**In this project:** `@daily`. Each run targets the previous day's `data_interval_start`.

### **`data_interval_start` / `data_interval_end`**

The time window a DAG run represents. For an `@daily` DAG scheduled at 2026-05-15, `data_interval_start = 2026-05-14 00:00` and `data_interval_end = 2026-05-15 00:00` — the run processes data for the previous day. Airflow fires the run _after_ the interval ends.

**In this project:** Passed into the extract task as `--run-date {{ data_interval_start | ds }}` so each run targets a single M5 day.

### **`catchup`**

DAG config. `catchup=True` (default): when you unpause a DAG, Airflow runs every missed interval since `start_date`. `catchup=False`: skip the backlog, but **still fire one run** for the most recent interval (caught Phil out — see [LEARNINGS.md / Airflow / catchup=False semantics]).

**In this project:** `catchup=False`. M5 history was already backfilled via the standalone Python extract; Airflow's job is only forward-going simulated freshness.

### **`max_active_runs`**

Caps how many runs of the same DAG can execute concurrently. `max_active_runs=1` serialises runs — handy for pipelines where one day's output is the next day's input.

**In this project:** `max_active_runs=1`.

### **Retries**

Per-task config: how many times Airflow should re-attempt a failed task before giving up. Each retry waits a configurable delay.

**In this project:** `retries=2` on every task — plenty for transient Azure SQL cold-start or Snowflake disconnects.

### **Sensor**

A special kind of operator that waits for an external condition to be true (file exists, partition lands, API returns OK) before letting downstream tasks run. Polls or uses a callback.

### **Hook**

Airflow's abstraction over an external system's connection — `SnowflakeHook`, `S3Hook`, `PostgresHook`. Wraps connection credentials defined in Airflow's Connections UI; gives tasks a clean way to talk to external services.

### **Airflow Connection**

A named record in Airflow's metadata database storing credentials for an external system. The recommended way to manage secrets in production (vs. `.env` file).

**Why it matters:** Listed as a Phase 6 stretch goal — moving from `.env` to Airflow Connections is a step toward production-grade.

### **Docker** (in this context)

Containerisation runtime — bundles an application plus all its dependencies (Python version, ODBC driver, OS libraries) into an isolated image that runs identically on any machine with Docker installed.

**In this project:** Airflow runs in Docker via `docker-compose`. The custom image at `airflow/Dockerfile` extends `apache/airflow:2.10.3-python3.11` with Microsoft ODBC Driver 17 so the DAG can call pyodbc.

### **`docker-compose`**

Tool for defining and running multi-container Docker applications via a YAML file. One command (`docker compose up -d`) starts all services declared in `docker-compose.yml`.

**In this project:** `airflow/docker-compose.yml` defines four services — postgres, airflow-init, airflow-webserver, airflow-scheduler.

---

## 7. Azure SQL & Cloud Concepts

### **Azure SQL Database**

Microsoft's fully managed cloud SQL Server. You get a database; Microsoft handles the VM, the SQL Server installation, the patching, the backups. Distinct from Azure SQL Managed Instance (more SQL-Server-compatibility, more cost) and SQL VM (run-your-own).

**In this project:** Source database `sqldb-m5-source` on Serverless General Purpose Free tier. Holds the M5 dataset bulk-loaded in Phase 1.

### **Azure SQL Managed Instance**

A higher-compatibility tier of Azure SQL — closer to "lift and shift a real SQL Server instance" with cross-database queries, CLR, SQL Agent. More expensive than Azure SQL Database; less managed than VM. Out of scope here.

### **Azure SQL VM**

A Windows or Linux virtual machine in Azure with SQL Server installed. You own the OS and the SQL Server install — maximum compatibility, maximum operational burden.

### **Serverless General Purpose**

An Azure SQL Database pricing tier where compute auto-scales and auto-pauses. Bills per **vCore-second** while active; while paused it costs only for storage. Pairs well with bursty workloads — your wallet doesn't care if you forget to shut it down at night.

**In this project:** Free tier. Pauses after ~1h idle; cold-start wake takes 30–60s on the first connection (which is why `wake_azure_sql()` exists).

### **Auto-pause**

Azure SQL Serverless feature — after a configurable idle period the database freezes (drops compute, keeps storage). Next connection triggers a wake-up that takes seconds. Saves cost on dev workloads dramatically.

**In this project:** Caused the first 40613 error mid-Phase-3. The `wake_azure_sql()` retry helper handles the wake-up transparently.

### **vCore-second**

The billing unit for Azure SQL Serverless. One vCore running for one second. Pricing scales linearly with vCore count and active time. The unit is small enough that a paused database costs essentially nothing.

### **Firewall rule** (Azure)

An IP allow-list entry on an Azure SQL server — without one, the database refuses connections from your machine. Configured in the Azure portal or via `New-AzSqlServerFirewallRule`.

**In this project:** One rule for `115.69.3.187` (Phil's home IP) added in Phase 1.

### **Resource group**

An Azure organisational unit — a logical container for related resources (the SQL server, the database, the storage account, the budget alert). Permissions and budgets attach at the resource-group level.

**In this project:** All Project 2 Azure resources sit in one resource group with a $50/month budget alert.

### **Budget alert**

A configurable spend threshold on a resource group or subscription. When crossed, Azure emails the owner. Cheapest insurance against "I forgot to shut something down for a month."

### **ODBC** (Open Database Connectivity)

A cross-database driver standard from Microsoft. ODBC Driver 17 for SQL Server is the binary that lets Python's `pyodbc` (or any other ODBC client) talk to Azure SQL over the wire.

**In this project:** Installed locally for Phase 1/2 work, and baked into the custom Airflow Docker image so the DAG container can connect to Azure SQL.

### **ODBC Driver 17 vs 18**

Two supported versions of the SQL Server ODBC driver. Driver 18 changed the default for `Encrypt` from `no` to `yes` (a TLS-by-default flip). Older connection strings break against Driver 18 if they assumed insecure default — example of "version-specific names that look interchangeable but aren't."

### **TLS** (Transport Layer Security)

The encryption protocol securing connections over a network — what the "S" in HTTPS stands for. Modern databases (Azure SQL, Snowflake) require TLS for all client connections.

### **`Encrypt=yes; TrustServerCertificate=no`**

Two ODBC connection-string parameters that together mean "TLS in transit AND validate the server's certificate against a trusted CA." Defaults vary by driver version — making them explicit is `CODE_QUALITY.md` criterion 4.

### **`Connection Timeout=`**

ODBC connection-string parameter controlling how long the client waits for the database to accept the connection. Phase 2's tuning: `90` seconds, deliberately longer than Azure SQL Serverless's 30–60s cold-start wake.

---

## 8. Python Ecosystem

### **Virtual environment** (`venv`)

An isolated Python installation tied to a single project. Packages installed inside the venv don't leak into the system Python or other projects. Activated per shell session.

**In this project:** `.venv/` at the project root. Activated via `.\.venv\Scripts\Activate.ps1` in PowerShell.

**Why it matters:** Without venvs, two projects with conflicting dependencies (different pandas versions, different SQLAlchemy versions) can't co-exist on the same machine.

### **pip**

Python's package installer. Reads from PyPI by default; installs into the active environment (venv or system).

### **`requirements.txt`**

A list of Python packages a project needs, one per line, optionally with version pins. `pip install -r requirements.txt` installs all of them.

**In this project:** Pinned to minimum versions only (e.g. `dbt-snowflake>=1.11.0`). Full lockfile generation deferred to end of Phase 4.

### **Lockfile**

A snapshot of exact versions of every installed package (including transitive dependencies), generated via `pip freeze > requirements-lock.txt`. Reproduces the same environment elsewhere. Trades flexibility (no auto-upgrades) for reproducibility.

### **Transitive dependency**

A package your dependencies depend on. `dbt-snowflake` pulls in `dbt-core`, which pulls in `Jinja2`, which pulls in `MarkupSafe`. You named one; pip installed forty.

**In this project:** Phase 2 caught an unintended transitive drift — installing `snowflake-connector-python` downgraded pandas from 3.0.3 to 2.3.3 because the connector hadn't qualified pandas 3.x.

### **`--no-deps`**

`pip install` flag: install this package, but don't install its dependencies. Used when you know dependencies are already satisfied (or shouldn't be installed at all on this platform).

**In this project:** `pip install apache-airflow==2.10.3 --no-deps` installed just enough Airflow source files for Pylance to resolve `from airflow.decorators import dag, task` on Windows, without dragging in Unix-only transitive deps that don't run on the host.

### **f-string**

Python 3.6+ string formatting syntax: `f"Hello, {name}"` interpolates `name` into the string. Replaces `.format()` and `%s`-style formatting. Faster, more readable, less error-prone.

**In this project:** Used throughout — every log line, every dynamic SQL string, every file path.

### **`pathlib`**

Python 3.4+ module for object-oriented filesystem paths. `Path("data/raw") / "calendar.csv"` instead of `os.path.join("data/raw", "calendar.csv")`. Cross-platform path handling, no string concatenation.

**In this project:** Standard throughout Python scripts. `CODE_QUALITY.md` criterion 1 (Currency) calls out `pathlib` over `os.path`.

### **Type hint**

Optional Python syntax for declaring the type of a variable, parameter, or return value: `def add(a: int, b: int) -> int:`. The runtime ignores them; tools like Pylance use them for static analysis.

### **Decorator**

A function that wraps another function to modify its behaviour. Applied with `@decorator_name` immediately above the function definition.

**In this project:** `@dag(...)` and `@task` from Airflow's TaskFlow API — wraps a plain Python function into an Airflow DAG / task.

### **Pylance / pyright**

Microsoft's Python static analyser used inside VS Code. Flags unresolved imports, type mismatches, unused variables. The yellow-squiggle source.

**In this project:** `pyrightconfig.json` at project root sets `extraPaths: ["scripts"]` so Pylance can resolve `import extract_azure_to_snowflake` from inside the DAG file.

### **`if __name__ == "__main__":`**

The Python idiom for "only run this block when this file is executed directly, not when it's imported as a module." Lets a script double as a library.

**In this project:** `extract_azure_to_snowflake.py` ends with this idiom so it can be both a CLI tool and an importable module called from Airflow.

### **pyodbc**

Python's most popular ODBC client. Speaks the [ODBC](#odbc-open-database-connectivity) protocol to anything that has an ODBC driver — SQL Server, Azure SQL, Postgres, MySQL.

**In this project:** The Azure SQL read side. Wrapped by SQLAlchemy for connection pooling and pandas integration.

### **SQLAlchemy**

Python's most popular database toolkit. Sits one layer above raw drivers (pyodbc, psycopg2), provides `create_engine()`, connection pooling, and the ORM nobody uses for analytics.

**In this project:** Just used as the connection abstraction wrapping pyodbc, for pandas' `read_sql_query()`. The ORM is unused.

### **pandas**

The in-memory tabular data library. `DataFrame` is the central type — basically a labelled 2D array. Used for extract-time row manipulation and as the wire format between database connectors.

**In this project:** `pd.read_sql_query(... chunksize=100_000)` reads from Azure SQL in 100k-row chunks; each chunk is passed to `write_pandas` for Snowflake load.

### **`snowflake-connector-python`**

Snowflake's official Python connector. The `[pandas]` extra pulls in `pyarrow` and unlocks `write_pandas` — the high-performance bulk loader.

### **`write_pandas`**

Function in `snowflake.connector.pandas_tools`. Bulk-loads a DataFrame into Snowflake by: encoding to Parquet, PUT-ing to internal stage, issuing `COPY INTO`. One Python call, three under-the-hood operations.

**In this project:** Sustained 22,000+ rows/sec on the `sales_train` extract — orders of magnitude faster than row-by-row INSERTs.

### **pyarrow**

Apache Arrow's Python bindings. Encodes pandas DataFrames into Parquet on the fly during Snowflake bulk load. Pulled in transitively by `snowflake-connector-python[pandas]`.

### **`python-dotenv`**

Library that reads a `.env` file and loads its key=value pairs into `os.environ`. Common pattern for development environments — gets credentials out of code without requiring a secret manager.

---

## 9. Git & GitHub

### **Git**

Distributed version control. Tracks the history of changes to files; lets multiple developers work on the same codebase without overwriting each other. Local-first — every clone is a full history of the project.

**Why it matters:** Self-rated 1/5 in `TEACHING_PREFERENCES.md`. The whole-project carry-forward discipline is "teach incidentally as we work" — every commit / branch / `.gitignore` decision is a teaching moment.

### **GitHub**

Microsoft's hosted Git service. Adds collaboration features (pull requests, issues, code review, CI/CD via Actions) on top of plain Git.

**In this project:** Repo public from day 1 at `https://github.com/Pheluciam/retail-demand-forecasting-project`.

### **Repository** (repo)

A Git project — its files plus its full history. Lives on disk (`.git/` folder at the project root) and optionally also on a remote like GitHub.

### **Commit**

A snapshot of the project at a point in time, identified by a SHA-1 hash. Commits form a chain — each one points back to its parent. The unit of "saved progress" in Git.

**In this project:** Convention is "one bundled commit per session" per `TEACHING_PREFERENCES.md`. Within-session pushes only when there's a reason.

### **Branch**

A named pointer to a commit. The default is usually `main` (formerly `master`). Branches let you work on a feature in isolation and merge it back when ready.

### **Remote**

A reference to a copy of the repo somewhere else — typically GitHub. The default remote name is `origin`.

### **`origin`**

Conventional name for the primary remote. `git push origin main` means "push the local main branch to the origin remote's main branch."

### **`push` / `pull` / `fetch`**

`git push` uploads local commits to a remote. `git fetch` downloads remote commits without merging. `git pull` is `fetch` + `merge` in one step.

### **`.gitignore`**

A file at the repo root listing path patterns Git should never track. Common entries: `.venv/`, `.env`, `__pycache__/`, `node_modules/`, `dbt_packages/`, `target/`, IDE caches.

**In this project:** Includes a `!dbt/profiles.yml` un-ignore line because the dbt-community default ignores all `profiles.yml` files; ours uses `env_var()` and is safe to commit.

### **Untracked vs ignored**

An untracked file is in the working directory but Git doesn't know about it (it might be a typo, a new file, a build artefact). An ignored file is _explicitly_ untracked — `.gitignore` matches it, Git treats it as invisible. Different states; different fixes.

### **Public vs private repo**

A GitHub setting on the repo. Public repos are visible to anyone; private repos are only visible to invited collaborators.

**In this project:** Public from day 1 — carry-forward discipline from Project 1.

### **Tag**

A named pointer to a commit, typically used to mark releases (`v1.0`, `v2.0`). Unlike branches, tags don't move.

### **Release**

GitHub's wrapper around a tag — adds release notes, downloadable artefacts, and surfaces a "Releases" tab on the repo page. The shippable-portfolio-piece marker.

**In this project:** Phase 6 will tag and release `v1.0`.

### **GitHub Actions**

GitHub's built-in CI/CD platform. Workflows are YAML files in `.github/workflows/` that run on push, PR, or schedule. Each workflow runs jobs on cloud-hosted runners.

**In this project:** Stretch goal for Phase 6 — workflow running `dbt parse`, `dbt test`, `sqlfluff lint` on every push to main.

---

## 10. PowerShell & Shell Basics

### **PowerShell**

Microsoft's modern Windows shell — pipes objects, not just text. The default scripting language on Windows for the last decade.

**In this project:** The shell Phil works in. Cheatsheets in PROJECT_CONTEXT and DBT_PIPELINE assume PowerShell syntax.

### **Shell**

A program that reads commands from input (keyboard or script) and runs them. PowerShell on Windows, bash/zsh on macOS/Linux, fish elsewhere. Different shells have different syntax — `$env:VAR` (PowerShell) vs `$VAR` (bash).

**Why it matters:** Self-rated 1/5 in `TEACHING_PREFERENCES.md`. Carry-forward discipline is "teach incidentally as we work."

### **`cd`** (Set-Location)

Change directory. `cd C:\Users\Phil\...` moves into that folder.

### **`Get-ChildItem`** (`ls`, `dir`)

List directory contents. PowerShell aliases `ls` and `dir` to `Get-ChildItem`.

### **Environment variable**

A named value available to running processes. Database passwords, account identifiers, file paths — anything a program might need without hard-coding.

### **`$env:VAR` vs `[Environment]::SetEnvironmentVariable(...)`**

PowerShell ways to read/set environment variables. `$env:VAR` is fast and lives only in the current PowerShell session. `[Environment]::SetEnvironmentVariable(name, value, 'Process')` is the same scope but uses .NET syntax — needed when constructing the variable name dynamically (e.g. inside a regex match loop).

**In this project:** The `.env` loader uses the `[Environment]::SetEnvironmentVariable` form because the variable name comes from a regex capture group, not a literal.

### **`.env` loader (PowerShell pipeline)**

The seven-line PowerShell incantation that reads `.env` line by line and loads each `KEY=VALUE` pair into the process environment:

```powershell
Get-Content .env | ForEach-Object {
    if ($_ -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}
```

`Get-Content` reads the file. `ForEach-Object` pipes each line through the script block. The regex matches a valid env-var line and captures the name and value. Run once per new PowerShell session before any dbt or Python command that reads `.env`.

### **`Test-NetConnection`**

PowerShell cmdlet that tests whether a TCP port is reachable. `Test-NetConnection sqldb-m5-source.database.windows.net -Port 1433` distinguishes "firewall is blocking me" from "the credentials are wrong."

**In this project:** Used as a diagnostic during Phase 1 Azure SQL connectivity setup.

### **Environment variable scope**

How long an env var lives and which processes see it. PowerShell scopes: `Process` (this shell only), `User` (this Windows user, all sessions), `Machine` (everyone on the machine). The `.env` loader uses `Process` — keeps secrets in memory only, gone when the shell closes.

---

## 11. Power BI & BI Concepts

### **Power BI**

Microsoft's BI tool. Connects to data sources, builds in-memory tabular models (the engine is essentially Analysis Services), renders dashboards, and publishes them to the Power BI Service. Free Desktop edition does everything except hosting.

**In this project:** Power BI Desktop, fed by Snowflake's native connector, will deliver a 5-page dashboard against the [marts](#mart-model-mart_) layer.

### **DAX** (Data Analysis Expressions)

Power BI's formula language. Like Excel formulas but designed for the columnar tabular model. Used to define [measures](#measure) and calculated columns.

**Why it matters:** Worth investing in if Power BI is part of your portfolio — separates BI-tool users from BI-platform-engineers.

### **Measure**

A DAX expression that calculates a value at query time, based on the current filter context (which slicers are selected, which rows are visible). Examples: `Total Sales = SUM(fact_daily_sales[revenue_amount_usd])`.

### **Explicit vs implicit measure**

**Implicit:** Power BI auto-creates an aggregation when you drag a numeric column onto a visual — `Sum of revenue_amount_usd`. **Explicit:** you write a DAX measure with a chosen name and definition. Explicit measures are reusable, testable, and labelled — implicit are throwaway.

**In this project:** Carry-forward discipline — every measure on every visual is explicit. Same rule as Project 1.

### **Calculated column**

A column added to a table by a DAX expression, evaluated at refresh time and stored. Looks like a real column to visuals. Generally **avoid** — push the calculation upstream into dbt where possible (carry-forward principle: "all display logic in dbt").

### **Relationship cardinality**

How many rows on each side of a relationship can join: **one-to-one**, **one-to-many** (the default for star schemas — one dim row to many fact rows), **many-to-many** (the slow one). Power BI infers cardinality on relationship creation; verify it.

### **Cross-filter direction**

A relationship's filter propagation: **single** (filter flows from the one-side to the many-side only — the safe default for star schemas) or **both** (bidirectional — necessary occasionally, slow and confusing usually).

**In this project:** Every relationship is single-direction Many-to-One from fact to dim. Discipline carry-forward from Project 1.

### **Slicer**

A Power BI visual that filters other visuals on the same page (or with sync, across pages). Date pickers, dropdown lists, slider ranges.

### **Drill-through**

A Power BI feature that lets a user right-click on a value, choose "drill through to detail page X," and land on another page filtered to that selection's context. The mechanism behind "click a region, see store-level breakdown."

### **Theme**

A JSON file defining colour palette, default fonts, and visual styling. Applied once at the report level. Makes the dashboard look intentional rather than thrown-together.

### **Format painter**

A Power BI tool that copies formatting from one visual to another. The discipline equivalent of "set up the first visual right, then propagate it everywhere."

### **Snowflake native connector** (Power BI)

The Power BI data source for Snowflake — Microsoft-maintained, talks Snowflake's wire protocol directly. Preferred over generic ODBC.

**In this project:** How Power BI will reach the marts layer in Phase 5.

---

## 12. Testing & QA

### **Unit test**

A test of one small piece of code in isolation — typically a single function. Fast, cheap, runs hundreds at a time. The base of the testing pyramid.

### **Integration test**

A test that exercises multiple pieces working together — typically a real database, a real API. Slower than unit tests, fewer of them.

### **Smoke test**

A minimal, fast test that proves the basic plumbing works — credentials valid, network reachable, library loads correctly. Run before any heavier testing.

**In this project:** `scripts/smoke_test_azure_sql.py` and `scripts/smoke_test_snowflake.py` — each one proves the connection stack works before any data movement starts.

### **Regression test**

A test added to catch a specific bug that was previously fixed, so it never recurs silently.

### **Parity check**

A test that compares two computations of the same value to confirm they match — Python's count of source rows vs SQL's `COUNT(*)` of destination rows. Catches drift between assumed and actual.

**In this project:** The extract script computes source row count before each load and confirms destination row count matches after. `sql/verify/02_phase2_extract_verification.sql` independently re-verifies from outside the script.

### **Sentinel pattern**

A defensive practice — deliberately preserve a "shouldn't happen" condition as a detectable signal rather than silently filtering it out. NULL after a LEFT JOIN is the canonical example; a `0` count when a `> 0` was expected is another.

**In this project:** The [LEFT-JOIN-as-sentinel pattern](#left-join-as-sentinel-pattern) in `stg_m5_sales_train`. Also the `verify_one_day` Airflow task — three counts, any zero raises RuntimeError.

### **Idempotency check**

A test that runs the same operation twice and confirms the second run is a no-op (or at least produces identical destination state). Catches scripts that look idempotent but aren't.

### **dbt generic test**

See [generic test](#generic-test).

### **dbt singular test**

See [singular test](#singular-test).

### **10-point code-quality audit**

Phil's project-specific code-review checklist (`CODE_QUALITY.md`) — seven core checks (currency, compactness, resource efficiency, privacy/security, workflow consistency, dev environment hygiene, upstream/downstream contract) plus three failsafes (idempotency, pre-flight/post-action verification, observable progress and actionable errors). Applied to every non-trivial script before "done."

**In this project:** Iterated to 10 points mid-Phase-3 after a gap (dev environment hygiene) surfaced.

---

## 13. CI/CD & DevOps

### **CI** (Continuous Integration)

The discipline of running automated checks (build, lint, test) on every commit or PR, before code is merged. Catches regressions before they reach main.

**In this project:** Stretch goal for Phase 6 — GitHub Actions running `dbt parse`, `dbt test`, `sqlfluff lint` on every push.

### **CD** (Continuous Deployment / Continuous Delivery)

CI's twin — automatically deploying code to production (or staging) after CI passes. Out of scope for this project.

### **Linter**

A tool that reads code and flags style or correctness issues without running it. Pylance for Python type-checking, sqlfluff for SQL style, pre-commit hooks combining many of them.

### **Formatter**

A tool that _rewrites_ code to enforce style automatically — Black for Python, Prettier for JS, sqlfluff format for SQL. Distinct from a linter (which just flags). Often used together.

### **`sqlfluff`**

A SQL linter and formatter that understands dbt. Run against `dbt/models/` to enforce CAPS keywords, consistent indentation, trailing commas. Configurable via `.sqlfluff` at the repo root.

**In this project:** Phase 6 stretch goal. Listed under code-quality audit as the one criterion deferred to closing.

### **`pre-commit`**

A framework that runs configured hooks (linters, formatters, secret scanners) before each `git commit`. Refuses the commit if any hook fails. Lives at `.pre-commit-config.yaml`.

### **`.env` pattern**

A convention for managing secrets in development: a file named `.env` at the project root holds `KEY=VALUE` lines, gitignored. A sibling `.env.example` is committed with placeholder values as documentation. Loaded into the process environment at runtime by `python-dotenv` (Python) or the PowerShell loader.

**In this project:** Used throughout — Azure SQL creds, Snowflake creds, dbt creds all flow through `.env`.

### **Secrets management**

The broader discipline of "don't put credentials in source code." Tiers, in increasing order of production-readiness: `.env` file → environment-variable injection → cloud secret manager (AWS Secrets Manager, HashiCorp Vault, Azure Key Vault).

---

## 14. Security & IAM

### **IAM** (Identity and Access Management)

The cloud term for "who can do what." Encompasses users, roles, policies, permissions. Every cloud has its own IAM service (AWS IAM, Azure RBAC + Entra ID, GCP IAM).

### **RBAC** (Role-Based Access Control)

The most common authorisation model: privileges are granted to roles, roles are granted to users. Users assume a role and inherit its privileges. Easier to manage than per-user permissions at scale.

**In this project:** Snowflake's authorisation is pure RBAC. The `RETAIL_ENGINEER` role gets the privileges; Phil's user assumes the role.

### **Principle of least privilege**

The discipline of granting each role only the privileges it actually needs — nothing more. Reduces the blast radius of a compromised credential.

**In this project:** ACCOUNTADMIN used only for one-time provisioning. Day-to-day work runs as `RETAIL_ENGINEER`, which has just enough privileges to operate inside `RETAIL_DB`.

### **Secret**

Any credential or sensitive value: password, API key, connection string, certificate private key. Secrets must never be committed to source control.

### **`.env` gitignore**

The single non-negotiable line in `.gitignore`: `.env` itself is **always** ignored, no exceptions. Forgetting this is how production passwords end up on public GitHub.

### **TLS** (Transport Layer Security)

See [TLS](#tls-transport-layer-security).

### **Server certificate validation**

The second half of TLS — confirming the server is who it says it is, by validating its certificate against a trusted CA chain. `TrustServerCertificate=no` enforces this; `TrustServerCertificate=yes` skips it (acceptable only in development).

### **SQL Authentication vs Microsoft Entra (Azure AD) Authentication**

Two ways to authenticate to Azure SQL. **SQL Authentication** uses a username + password stored in the database. **Entra Authentication** federates to the company's identity provider — same login as Outlook. Entra is the modern default; SQL auth still works and is simpler for portfolio projects.

**In this project:** SQL Authentication — username + password from `.env`.

---

## 15. Project-Specific Terms [Project 2]

### **M5 Forecasting dataset** `[Project 2]`

A public Kaggle dataset published by Walmart in 2020 for the M5 Forecasting competition. Contains daily sales for ~30,000 SKUs across 10 Walmart stores in California, Texas, and Wisconsin between 2011-01-29 and 2016-06-19. Five CSV files: `calendar.csv`, `sell_prices.csv`, `sales_train_validation.csv`, `sales_train_evaluation.csv`, `sample_submission.csv`.

**In this project:** Three are loaded — `calendar`, `sell_prices`, `sales_train_evaluation`. The "evaluation" file contains the full 1,941-day sales horizon (the "validation" file is a 28-day-shorter subset, dropped to avoid double-counting).

### **SNAP flag** `[Project 2]`

**S**upplemental **N**utrition **A**ssistance **P**rogram — the US food-stamp scheme. The M5 calendar contains three boolean SNAP columns (`snap_CA`, `snap_TX`, `snap_WI`) flagging whether SNAP benefits could be spent in each state on a given day. Used as a demand-driver feature in the original competition.

**In this project:** Carried through staging as `snap_ca`, `snap_tx`, `snap_wi` (snake-cased). Will surface as filterable dimensions in `dim_calendar`.

### **`wm_yr_wk`** `[Project 2]`

Walmart's internal fiscal-year-and-week identifier — a 5-digit integer like `11101` (year 2011, week 1). The natural key between `calendar` and `sell_prices`: prices change on a weekly cadence, not daily.

**In this project:** Used as the join key when attaching prices to sales in `int_sales_with_prices`.

### **`d_NNNN` day identifier** `[Project 2]`

The M5 dataset's wide-table day-column naming scheme: `d_1`, `d_2`, ..., `d_1941`. Each is a sequential day from the dataset's start (2011-01-29 = `d_1`). The calendar file provides the mapping to real dates.

**In this project:** Stored as `VARCHAR(10)` in RAW. Translated to a real `sale_date DATE` in the staging layer via LEFT JOIN to `stg_m5_calendar`. The translation is the whole reason `stg_m5_sales_train` uses the CTE pattern.

### **FOODS / HOUSEHOLD / HOBBIES** `[Project 2]`

The three top-level product departments in the M5 hierarchy: FOODS (groceries), HOUSEHOLD (cleaning, paper goods), HOBBIES (toys, crafts). Each splits into sub-departments and SKUs. ~58M sales rows total, split roughly 60/25/15 by row count.

**In this project:** Will become a `dim_item` hierarchy column for slicer-driven Power BI breakdowns.

### **Simulated freshness (Option B ingestion pattern)** `[Project 2]`

The chosen ingestion pattern for this project: bulk-load all M5 history into Azure SQL once, then have Airflow extract **one date-partitioned slice per scheduled run** (`WHERE sale_date BETWEEN data_interval_start AND data_interval_end`). Makes the dbt incremental models, tests, and freshness alerts behave like a live pipeline rather than theatre — Airflow is genuinely advancing the dataset one day per run, even though no new source data is actually arriving.

**Why it matters:** The contrast pattern (Option A) would be "load everything once, schedule Airflow to no-op" — which doesn't exercise any of the interesting orchestration patterns. Option B trades a bit of complexity for a pipeline that demonstrates the patterns it claims to.

### **Three-layer documentation pattern** `[Project 2]`

Phil's convention for every code-shaped file in this project: (a) **verbose-version-in-chat** with heavy comments — the in-session learning artefact; (b) **clean-professional-version-on-disk** with only non-obvious-choice comments — what gets committed; (c) **walkthrough-markdown-alongside** (`<COMPONENT>_PIPELINE.md`) — depth for portfolio visitors. Locked mid-Phase-4-session-1. First instances: `EXTRACT_PIPELINE.md`, `DBT_PIPELINE.md`.

### **Comments-above-the-line** `[Project 2]`

Phil's convention for in-file code comments: explanations live on their own line **immediately above** the line they document, never at end-of-line. End-of-line comments push past chat code-block width and force horizontal scroll. Locked mid-Phase-4-session-1.

### **`wake_azure_sql` helper** `[Project 2]`

A small retry function in `scripts/extract_azure_to_snowflake.py` that catches Azure SQL Free Serverless cold-start error codes (40613, 40197), waits 45 seconds, and retries up to 3 times. Earned its keep on its first real Airflow run when Azure SQL had auto-paused over lunch.

### **`m5_daily_extract` DAG** `[Project 2]`

The single Airflow DAG in `airflow/dags/m5_daily_extract.py`. Two tasks: `extract_one_day` (calls the Python extract for one M5 day) followed by `verify_one_day` (queries Snowflake to confirm rows landed). `@daily`, `start_date=2014-01-01 Australia/Melbourne`, `catchup=False`, `max_active_runs=1`, `retries=2`.

### **Backfill cutoff at 2014-01-01** `[Project 2]`

A locked design decision (`LEARNINGS.md`, 2026-05-13): the standalone backfill loaded 2011-01-29 through 2013-12-31; Airflow takes over from 2014-01-01 onward. Splits the data into "historical" (already-landed) and "incremental" (Airflow-managed) cleanly.

### **`RETAIL_DB.RAW` / `STAGING` / `INTERMEDIATE` / `WAREHOUSE` / `MARTS`** `[Project 2]`

The five Snowflake schemas of this project, each owned by `RETAIL_ENGINEER`. RAW is loaded by Airflow; the rest by dbt via the `generate_schema_name` macro.

### **`fact_daily_sales`** `[Project 2]`

The central fact table of the warehouse layer. Grain: one row per (store, item, day). Surrogate keys to `dim_item`, `dim_store`, `dim_calendar`. Partitioned/clustered on `sale_date`, built [incrementally](#materialization). Power BI never queries this directly — only through marts.

### **`dim_item` / `dim_store` / `dim_calendar`** `[Project 2]`

The three dimension tables of the warehouse layer. Surrogate keys via `dbt_utils.generate_surrogate_key`. Each carries both `<entity>_key` (surrogate) and `<entity>_id` (natural) per the locked naming convention.

---

## 16. Acronyms Quick Reference

| Acronym    | Expansion                                      | Section                                                                |
| ---------- | ---------------------------------------------- | ---------------------------------------------------------------------- |
| **ACID**   | Atomicity, Consistency, Isolation, Durability  | [SQL](#3-sql--database-concepts)                                       |
| **AD**     | Active Directory (Microsoft)                   | [Security](#14-security--iam)                                          |
| **AWS**    | Amazon Web Services                            | [Snowflake](#4-snowflake)                                              |
| **BI**     | Business Intelligence                          | [Power BI](#11-power-bi--bi-concepts)                                  |
| **CA**     | Certificate Authority                          | [Security](#14-security--iam)                                          |
| **CD**     | Continuous Deployment / Delivery               | [CI/CD](#13-cicd--devops)                                              |
| **CDC**    | Change Data Capture                            | [DE Core](#1-data-engineering-core)                                    |
| **CI**     | Continuous Integration                         | [CI/CD](#13-cicd--devops)                                              |
| **CLI**    | Command-Line Interface                         | —                                                                      |
| **CTE**    | Common Table Expression                        | [SQL](#3-sql--database-concepts)                                       |
| **DAG**    | Directed Acyclic Graph / Airflow pipeline      | [SQL](#3-sql--database-concepts), [Airflow](#6-airflow--orchestration) |
| **DAX**    | Data Analysis Expressions (Power BI)           | [Power BI](#11-power-bi--bi-concepts)                                  |
| **DDL**    | Data Definition Language                       | [SQL](#3-sql--database-concepts)                                       |
| **DE**     | Data Engineering / Data Engineer               | —                                                                      |
| **DML**    | Data Manipulation Language                     | [SQL](#3-sql--database-concepts)                                       |
| **ELT**    | Extract, Load, Transform                       | [DE Core](#1-data-engineering-core)                                    |
| **ETL**    | Extract, Transform, Load                       | [DE Core](#1-data-engineering-core)                                    |
| **GCP**    | Google Cloud Platform                          | [Snowflake](#4-snowflake)                                              |
| **HTTPS**  | HTTP Secure (HTTP over TLS)                    | [Security](#14-security--iam)                                          |
| **IAM**    | Identity and Access Management                 | [Security](#14-security--iam)                                          |
| **IDE**    | Integrated Development Environment             | [Python](#8-python-ecosystem)                                          |
| **LTZ**    | Local Time Zone (Snowflake variant)            | [Snowflake](#4-snowflake)                                              |
| **MDM**    | Master Data Management                         | —                                                                      |
| **NTZ**    | No Time Zone (Snowflake variant)               | [Snowflake](#4-snowflake)                                              |
| **ODBC**   | Open Database Connectivity                     | [Azure SQL](#7-azure-sql--cloud-concepts)                              |
| **OLAP**   | Online Analytical Processing                   | [DE Core](#1-data-engineering-core)                                    |
| **OLTP**   | Online Transaction Processing                  | [DE Core](#1-data-engineering-core)                                    |
| **PII**    | Personally Identifiable Information            | [Security](#14-security--iam)                                          |
| **PR**     | Pull Request (GitHub)                          | [Git](#9-git--github)                                                  |
| **RBAC**   | Role-Based Access Control                      | [Security](#14-security--iam)                                          |
| **S&OP**   | Sales and Operations Planning                  | [Project 2](#15-project-specific-terms-project-2)                      |
| **SCD**    | Slowly Changing Dimension                      | [Dim Modelling](#2-dimensional-modelling)                              |
| **SHA**    | Secure Hash Algorithm (used in Git commit IDs) | [Git](#9-git--github)                                                  |
| **SKU**    | Stock Keeping Unit                             | [Project 2](#15-project-specific-terms-project-2)                      |
| **SNAP**   | Supplemental Nutrition Assistance Program      | [Project 2](#15-project-specific-terms-project-2)                      |
| **SQL**    | Structured Query Language                      | [SQL](#3-sql--database-concepts)                                       |
| **T-SQL**  | Transact-SQL (Microsoft's SQL dialect)         | [SQL](#3-sql--database-concepts)                                       |
| **TLS**    | Transport Layer Security                       | [Security](#14-security--iam)                                          |
| **TZ**     | Time Zone                                      | [Snowflake](#4-snowflake)                                              |
| **UPSERT** | Update + Insert (no formal expansion)          | [SQL](#3-sql--database-concepts)                                       |
| **UTC**    | Coordinated Universal Time                     | [Snowflake](#4-snowflake)                                              |
| **WSL**    | Windows Subsystem for Linux                    | [Shell](#10-powershell--shell-basics)                                  |
| **XS**     | X-SMALL (Snowflake warehouse size)             | [Snowflake](#4-snowflake)                                              |
| **YAML**   | YAML Ain't Markup Language (recursive acronym) | [dbt](#5-dbt)                                                          |

---

_End of glossary v1. Extended organically as new terms come up in subsequent sessions. Tag `[Project 2]` marks entries that are specific to this project and should be stripped before carry-forward to Project 3._
