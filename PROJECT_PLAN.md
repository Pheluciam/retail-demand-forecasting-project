# Retail Demand & Forecasting Pipeline — Project Plan

> Working document for Project #2 of the data engineering portfolio.
> Architecture diagram and overview are employer-shareable.
> Created: 2026-05-09. Last meaningfully updated: 2026-05-15 (Phase 3 in flight).

---

## At a glance

A **production-grade retail demand-planning analytics platform** built end-to-end on a hybrid Microsoft + modern-data-stack architecture. Real Walmart sales data (M5 dataset) is ingested from MS SQL Server into a Snowflake cloud warehouse via scheduled Airflow jobs, transformed through a partitioned star schema with dedicated marts using dbt, and surfaced as a five-page Power BI dashboard for an operations / S&OP audience.

**The headline:** orchestration. The pipeline runs end-to-end on a schedule, with proper failure handling, tests, and CI — not button-pressed like Project #1.

|                      |                                                                 |
| -------------------- | --------------------------------------------------------------- |
| **Project name**     | Retail Demand & Forecasting Pipeline                            |
| **Repo slug**        | `retail-demand-forecasting-project`                             |
| **Domain**           | Retail demand planning, S&OP operations, forecasting            |
| **Dataset**          | M5 Forecasting (Kaggle, public — Walmart daily sales 2011–2016) |
| **Estimated effort** | 12–16 sessions × 2–3 hours each (~30–45 hours total)            |

---

## Architecture

```mermaid
flowchart LR
    K["Kaggle M5<br/>Public Dataset"]
    MS[("MS SQL Server<br/>OLTP Source")]
    AF["Apache Airflow<br/>Docker"]
    SF[("Snowflake<br/>Cloud Warehouse")]
    DBT["dbt<br/>Transformations"]
    PBI["Power BI<br/>5-Page Dashboard"]
    GH["GitHub Actions<br/>CI/CD"]

    K -->|Initial load| MS
    MS -->|Daily extract| AF
    AF -->|COPY INTO| SF
    SF <-->|Staging &rarr; Warehouse &rarr; Marts| DBT
    SF -->|Native connector| PBI
    GH -.->|parse / tests / lint| DBT
```

GitHub renders this Mermaid block natively — no image export needed.

### dbt layering

```mermaid
flowchart TB
    SRC["Snowflake Raw Schema<br/>(loaded by Airflow)"]
    STG["Staging Models<br/>(stg_*)<br/>type cast, rename, unpivot wide-to-long"]
    INT["Intermediate Models<br/>(int_*)<br/>business logic joins"]
    WH["Warehouse Models<br/>(fact_*, dim_*)<br/>star schema, partitioned, incremental"]
    MART["Marts<br/>(mart_*)<br/>pre-aggregated, one per dashboard page"]

    SRC --> STG --> INT --> WH --> MART
```

---

## Locked decisions (no more drift)

| Decision                  | Choice                                                                                                                                                                                                                                                                                                                                        |
| ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Project name**          | Retail Demand & Forecasting Pipeline                                                                                                                                                                                                                                                                                                          |
| **Repo slug**             | `retail-demand-forecasting-project`                                                                                                                                                                                                                                                                                                           |
| **Domain**                | Retail demand planning, S&OP operations, forecasting (forecast surfacing only — no ML modelling pipeline)                                                                                                                                                                                                                                     |
| **Source database**       | Azure SQL Database — Serverless General Purpose Free tier with auto-pause                                                                                                                                                                                                                                                                     |
| **Dataset**               | M5 Forecasting (Kaggle, public)                                                                                                                                                                                                                                                                                                               |
| **Cloud warehouse**       | Snowflake (free trial, sign up when ready in Phase 2)                                                                                                                                                                                                                                                                                         |
| **Transformation**        | dbt-snowflake with `dbt_utils`, tests, packages, marts layer                                                                                                                                                                                                                                                                                  |
| **Architecture**          | Kimball star + lean marts (analyst-facing) + partitioned incremental fact builds. Power BI consumes the warehouse star (fact + dims) directly for slice/dice flexibility; marts hold pre-aggregations only where they earn their keep. See `LEARNINGS.md` → "2026-05-17 — Lean marts layer + analyst-facing star schema". |
| **Orchestration**         | Apache Airflow in Docker                                                                                                                                                                                                                                                                                                                      |
| **BI tool**               | Power BI (Service if licence allows, Desktop otherwise)                                                                                                                                                                                                                                                                                       |
| **CI/CD**                 | GitHub Actions running `dbt parse` + tests + `sqlfluff` (stretch goal)                                                                                                                                                                                                                                                                        |
| **API ingestion**         | Deferred to Project #3 (financial markets / lakehouse)                                                                                                                                                                                                                                                                                        |
| **Forecasting modelling** | Deferred (forecast surfacing in dbt only — 28-day baseline)                                                                                                                                                                                                                                                                                   |
| **Ingestion pattern**     | **Simulated freshness (Option B):** all M5 history bulk-loaded into Azure SQL once. Airflow DAG extracts ONE date-partitioned slice per scheduled run (`WHERE sale_date BETWEEN '{{ data_interval_start }}' AND '{{ data_interval_end }}'`). Makes incremental dbt models, tests, and alerts behave like a live pipeline rather than theatre. |

---

## Pre-flight checklist

Pre-flight checklist completed during Phase 0.
See `PROJECT_CONTEXT.md` → "Pre-flight check results" for the verified state.

### Decisions confirmed post-checklist

- Source database hosting: **Azure SQL Database** (Serverless General Purpose Free tier, auto-pause).
- Power BI publication: **Desktop + screenshots in README** (no Service licence).
- CI/CD scope: **stretch goal only** — `dbt parse` + tests + `sqlfluff` via GitHub Actions if time allows in Phase 6.

---

## Session-by-session timeline

Sessions are ~2–3 hours each. Times are honest estimates including troubleshooting. Pace is up to you — this is a "couple of sessions a week" or "every day if motivated" plan, not a deadline.

| Phase                                | Sessions  | What happens                                                                                                                                                                                                                                                                                                                                                                             | Deliverables at end                                                                    |
| ------------------------------------ | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| **Phase 0 — Setup**                  | 1         | Pre-flight checks confirmed. Final hosting decisions. Repo created on GitHub (public). Folder structure scaffolded with `README.md`, `LEARNINGS.md`, `PROJECT_CONTEXT.md`, `.gitignore`. Python venv. Naming conventions document committed. First commit pushed                                                                                                                         | Empty repo, conventions doc, README skeleton                                           |
| **Phase 1 — Source database**        | 1–2       | MS SQL Server up (Docker or Azure SQL). Connect from VS Code / Azure Data Studio. M5 raw CSVs downloaded from Kaggle. Bulk load all 5 M5 files into MS SQL Server. Verify row counts, character encoding, sample queries                                                                                                                                                                 | 6 raw tables in MS SQL Server with verified data                                       |
| **Phase 2 — Snowflake + extraction** | 2–3       | Snowflake free trial signed up (clock starts). Warehouse / database / schema / role provisioned. Python extract-and-load job: MS SQL → Snowflake staging via `pyodbc` → Pandas → `snowflake-connector-python` → `COPY INTO`. **Extract is date-parameterised from day 1** (takes a `run_date` arg). Test single-table extract first, then all-tables                                     | All 6 raw tables landed in Snowflake `RAW` schema; extract script accepts a date param |
| **Phase 3 — Airflow orchestration**  | 2         | Airflow Docker compose stack up locally. First DAG: extract MS SQL → load Snowflake → run on schedule, **passing `{{ data_interval_start }}` to the date-parameterised extract so each run picks up one new day of M5 history (simulated freshness)**. Failure handling and email/log alerts. Containerise the Python extract job. Manual trigger and scheduled trigger both validated   | Working DAG runs end-to-end on schedule, advancing one M5 day per run                  |
| **Phase 4 — dbt transformations + orchestration**    | 5–6       | dbt-snowflake configured. Sources defined. **Staging layer** (M5 already long from Python load). **Intermediate layer**: `int_sales_with_prices`. **Warehouse layer**: `dim_item`, `dim_store`, `dim_calendar`, `fact_daily_sales` (incremental, clustered on `sale_date`). dbt tests on every dim's primary key. Surrogate keys via `dbt_utils.generate_surrogate_key`. **Marts layer (lean):** `mart_executive_overview` only — pre-aggregated daily summary for the home page. Other Power BI pages slice the warehouse star directly. See `LEARNINGS.md` "Lean marts layer" entry. **Phase 4 closes with Airflow ↔ dbt wiring via Astronomer Cosmos** (session 6) so each dbt model becomes its own Airflow task in the existing `m5_daily_extract` DAG, with full lineage visible in the Airflow UI. | Full dbt project building cleanly with passing tests + Airflow-orchestrated dbt build |
| **Phase 5 — Power BI + forecasting**  | 5–6       | Snowflake native connector configured (DirectQuery vs Import evaluated empirically per page). Power BI semantic model with relationships from `WAREHOUSE.fact_*` + `dim_*` (lean-marts pattern). **All five pages fully built**: Executive Overview (from `mart_executive_overview`), Demand by Hierarchy, Promotion & Price, Seasonality & Calendar, Forecast vs Actual. **Forecasting layer built end-to-end** — time-series forecasts via Snowflake Cortex ML functions (or Python statsmodels / Prophet — decided session 5 open), results written back to Snowflake, new `mart_forecast_vs_actual` dbt model joining forecasts to fact, `is_incremental` patterns where appropriate. Full DAX measure library (time intelligence, period-over-period, dynamic top-N, dynamic format strings). Cross-page sync slicers, drill-throughs, theme. Performance tuning (VertiPaq compression analysis, BI-side aggregations if needed). `POWERBI_PIPELINE.md` walkthrough doc shipped matching EXTRACT_PIPELINE / DBT_PIPELINE depth | Polished `.pbix` file with 5 fully-built pages including working forecasts + new mart |
| **Phase 6 — CI/CD + ship**            | 2–3       | README expanded with architecture diagram, screenshots of all 5 Power BI pages, "how to run" section, business problem statement, tech-stack rationale, key learnings. **GitHub Actions CI fully wired** (no longer stretch): `dbt parse` + `dbt test` + dbt slim CI (only changed models + downstream) + `sqlfluff` lint + markdown lint, green badge in README. **`dbt docs generate` hosted on GitHub Pages** (no longer stretch). `LEARNINGS.md` final pass + "What I'd do differently next time" populated. Final closing 10-point + phase-boundary structural audit across the whole project. Tag `v1.0` release. Public repo confirmed | Complete portfolio-grade project, all stretch goals shipped as baseline |
| **Total**                            | **18–23** |                                                                                                                                                                                                                                                                                                                                                                                          |                                                                                        |

---

## Carry-forward principles from Project #1

These are non-negotiable from day 1, locked from `LEARNINGS.md` carry-forward section.

1. **Git initialised and pushed to GitHub before any other work.** First commit = empty repo. Public from day 1
2. **`LEARNINGS.md` and `README.md` created day one**, updated mid-project not just at end
3. **dbt tests on every dim's primary key** (`unique` and `not_null` minimum)
4. **`feed_id` / source identifier carried through every layer** — even though M5 is single-source, this discipline applies for any reference data joined in
5. **Naming conventions decided and documented BEFORE building any models** (see below)
6. **`dbt_utils.generate_surrogate_key()`** for surrogate keys — not manual `||` concatenation
7. **All display logic in dbt**, not Power BI — pretty labels live in the warehouse
8. **Verify column units against actual data on ingestion** — don't trust column-name suffixes
9. **`::INTERVAL` over `::TIME`** for any time arithmetic that might hit edge cases
10. **Architectural decisions documented as they're made** — every dbt-vs-DAX-vs-mart call captured in `LEARNINGS.md` with a one-liner

### Naming conventions

| Object                  | Convention                             | Example                                 |
| ----------------------- | -------------------------------------- | --------------------------------------- |
| All identifiers         | `snake_case`                           | `daily_sales`                           |
| Surrogate keys          | `<entity>_key`                         | `item_key`, `store_key`                 |
| Natural / business keys | `<entity>_id`                          | `item_id`, `store_id`                   |
| Fact tables             | `fact_<grain>_<entity>`                | `fact_daily_sales`                      |
| Dim tables              | `dim_<entity>`                         | `dim_item`, `dim_store`, `dim_calendar` |
| Staging models          | `stg_<source>_<entity>`                | `stg_m5_sales`                          |
| Intermediate models     | `int_<purpose>`                        | `int_sales_with_prices`                 |
| Mart models             | `mart_<purpose>`                       | `mart_daily_sales_by_store`             |
| Date column in facts    | `sale_date` (DATE type, partition key) |                                         |
| Currency / amounts      | `<noun>_amount_usd` (units in name)    | `revenue_amount_usd`                    |

---

## Risk register & mitigations

| Risk                                                        | Likelihood | Impact | Mitigation                                                                                             |
| ----------------------------------------------------------- | ---------- | ------ | ------------------------------------------------------------------------------------------------------ |
| RAM constraint (Docker stack heavy)                         | Medium     | High   | Pre-flight RAM check; fall back to Airflow LocalExecutor or Azure SQL if tight                         |
| Snowflake 30-day trial expires mid-project                  | Medium     | Medium | Don't sign up until Phase 2. X-SMALL warehouse only. Suspend when not in use                           |
| M5 wide-to-long shape causes ingestion confusion            | Low        | Low    | Plan unpivot in dbt staging from day 1 — flagged in `stg_m5_sales`                                     |
| Power BI choking on 32.9M-row warehouse fact                | Low        | Medium | **Superseded 2026-05-17.** Power BI connects to `WAREHOUSE.fact_*` + `dim_*` directly for analyst-facing pages, and to `MARTS.mart_*` for pre-aggregated rollups. VertiPaq compression handles the fact size on Snowflake's XS warehouse. Empirically verify before relying on it. |
| UTF-8 / encoding bugs (Project #1 repeat)                   | Low        | Medium | Explicit `encoding='utf-8'` on all Python file ops. `nvarchar` (not `varchar`) in MS SQL Server        |
| Naming inconsistency drift                                  | Medium     | Medium | Conventions table above is committed to repo Phase 0. No exceptions                                    |
| Airflow first-time-setup pain                               | High       | Medium | Use Astronomer's official `docker-compose.yml` template — well-documented, low-friction starting point |
| Scope creep (weather API, additional pages, lakehouse)      | Medium     | Medium | **Updated 2026-05-17**: forecasting is now in-scope (M5 is literally a forecasting dataset; deferring it weakens the portfolio narrative). Weather API, additional pages, lakehouse architecture remain out-of-scope and reserved for Project #3. This document is the contract |
| Auto-detected relationships in Power BI (Project #1 repeat) | Medium     | Low    | Disable autodetect on first model load. Manage Relationships pass after every refresh                  |

---

## Definition of "shippable"

Project #2 ships when **all of these** are true (updated 2026-05-17 — former stretch goals promoted to baseline; full scope locked in):

- Pipeline runs end-to-end automatically (Airflow scheduled, not button-pressed)
- All dbt models have at least basic tests; tests pass
- Cloud warehouse (Snowflake), not local
- Architecture diagram in README (the Mermaid block above)
- README explains the business problem, the architecture, and how to run it
- Screenshots of **all five** Power BI pages in the README (not just one)
- All five pages fully built — Executive Overview, Demand by Hierarchy, Promotion & Price, Seasonality & Calendar, **Forecast vs Actual with working forecasts** (not stubbed)
- Forecasting layer built end-to-end — model trained or Cortex invoked, results written back to Snowflake, joined to fact via `mart_forecast_vs_actual`
- `LEARNINGS.md` populated through the project (not just end)
- Repo public on GitHub from day 1
- **GitHub Actions CI passing on `main` branch** (green badge in README)
- **`dbt docs generate` hosted on GitHub Pages**
- Tagged `v1.0` release

**Remaining stretch goals** (genuinely optional, would not block shipping):

- Power BI Service live link (in addition to screenshots)
- `.env` secrets migrated to Airflow Connections (refactor, not feature)
- `dbt-snowflake` upgrade to whatever the latest minor is at v1.0 time

---

## What this project deliberately does NOT do

To avoid scope creep, these remain out (updated 2026-05-17 — forecasting removed from this list and moved into Phase 5 in-scope):

- **Streaming / real-time** ingestion. Batch daily is the headline cadence
- **Multiple cloud providers.** Snowflake on AWS-backed default region; nothing on Azure/GCP simultaneously
- **API ingestion.** Reserved for Project #3
- **Lakehouse / medallion architecture.** Reserved for Project #3
- **Multiple BI tools.** Power BI only — Tableau or Looker are scope creep here
- **Deep ML / hyperparameter tuning.** The forecasting layer uses one or two well-chosen out-of-the-box methods (Snowflake Cortex ML functions, or Prophet / exponential smoothing in Python); model evaluation is included but bake-off / extensive feature engineering is reserved for any future ML-specific project

---

## Cross-references

- `TEACHING_PREFERENCES.md` — how Phil works with Claude (carry-forward, not project-specific)
- `LEARNINGS.md` — running journal, populated as the project progresses
- `PROJECT_CONTEXT.md` — current state and immediate next steps (created Phase 0)
- `README.md` — public-facing project intro for hiring managers (built up over Phase 6)

---

## Status

|                  |                                                                        |
| ---------------- | ---------------------------------------------------------------------- |
| **Phase**        | Phase 5 — session 5.7 **closed**. Polish pass shipped on 3 of 5 PBI pages end-to-end: Executive Overview (City Park theme, compact KPI row with renamed labels, trend chart with 30-day MA dashed black overlay, $-formatted tooltips via measure-level Currency format, Active Items numeric format fix), Demand by Hierarchy (2×2 grid with ~20px gaps, category-keyed bar colors via Color → fx Rules on CAT_ID, matrix `%GT` prefix stripped, all titles renamed), Promotion & Price (column chart category-colored via the **Columns** section not Bars, donut retitled with `Category, percent of total` detail labels and City Park blue/purple slices, scatter with bubble Size bound to Total Revenue + per-series Markers coloring + custom shapes per category, currency-formatted axes). Cross-page Date + Category slicer sync confirmed across all 5 pages. 5.6 backlog format fixes burned down (Revenue Share % → percentage, Forecast vs Actual slicer compaction, scatter Size field, orphan-Measure check). 2 new LEARNINGS captured (PBI format pane section names vary by visual type — Bars/Columns/Markers/Slices; new Card visual Reference labels field well variant-dependent — basic-license PBI Desktop missing it). Next: Phase 5 session 5.8 — finish Seasonality & Calendar + Forecast vs Actual polish; drill-through actions; VertiPaq Analyzer dim-cardinality check; end-to-end DAG smoke test; delete unused measures; bundled commit. Total project: 18-23 sessions; ~19-20 sessions done so far; ~1-2 sessions remaining |
| **Last updated** | 2026-05-21                                                             |
| **Next step**    | See `PROJECT_CONTEXT.md` → "Where we are right now" for the live state |
