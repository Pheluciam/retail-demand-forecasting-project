# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Live state of the project. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-14 (Phase 2 closed; Phase 3 = Airflow opens next session).

---

## Where we are right now

**Current phase:** Phase 2 — ✅ DONE. Next session opens **Phase 3 (Airflow)**.

**Last action (2026-05-14 — Phase 2 session 3):** 3-year backfill executed and verified end-to-end. 35.6M rows landed from Azure SQL into Snowflake in 27.3 minutes via a single PowerShell command. All nine Phase 2 sub-tasks now complete:

1. ✅ Snowflake free trial signed up
2. ✅ Snowflake account provisioned (warehouse, database, schema, role, grants)
3. ✅ Snowflake creds in `.env`
4. ✅ `snowflake-connector-python[pandas]` 4.5.0 installed
5. ✅ `scripts/smoke_test_snowflake.py` written and passing
6. ✅ `sql/snowflake/01_create_raw_tables.sql` run — three RAW tables ready
7. ✅ `scripts/extract_azure_to_snowflake.py` written (~440 lines including comments)
8. ✅ Smoke-tested end-to-end on increasing windows (1 day, idempotent re-run, 1 day all tables, 7 days all tables)
9. ✅ **3-year backfill executed (2011-01-29 → 2013-12-31) — 27.3 min wall-clock, parity OK on all three tables, end-to-end verification via both script-level and independent SQL queries.**

**Files added this session (Phase 2 session 3):**

- `sql/verify/02_phase2_extract_verification.sql` — Azure SQL source-side row-count verification queries for the 3-year backfill window. Mirror to the Snowflake-side check.
- `EXTRACT_PIPELINE.md` (project root) — interview-friendly architecture walkthrough of the Azure SQL → Python → Snowflake pipeline. Mermaid flowchart + stage-by-stage + library breakdown + the two key function calls (`read_sql_query`, `write_pandas`) + "why this design holds up" talking points.
- `logs/backfill_3yr_*.log` — captured stdout from the backfill run (gitignored).

**Files updated this session:**

- `sql/snowflake/02_extract_smoke_tests.sql` — added Section 5: backfill verification with window-filtered counts vs math-derived expected values.
- `LEARNINGS.md` — three additions: (a) Snowflake section: "3-year backfill economics" entry with final per-table numbers and throughput; (b) Mistakes & diagnoses: error 40613 cold-start fast-fail; (c) Design decisions: "Validated 2026-05-14" confirmation on the fixed-scan-cost decision.
- `PROJECT_CONTEXT.md` (this file)

**Headline outcomes from this session:**

- **3-year backfill: 27.3 min wall-clock** for 35.6M rows across 3 tables. Against 60-90 min prediction and 40-hour original fear.
- **Sustained throughput in production:** sell_prices ~35,500 rows/sec; sales_train ~22,000 rows/sec. Both higher than session 2 spot-test measurements (~3.4× and ~1.5× respectively) — bigger chunks amortise overhead better.
- **End-to-end parity proven two independent ways:** (1) script's own pre-flight + post-action verification (Azure SQL source count == Snowflake destination written count), and (2) independent SQL queries against both databases run from Snowsight and Azure portal Query editor — all `OK / OK / OK` for calendar (1,068), sell_prices (3,040,105), sales_train (32,563,320).
- **One real failure mode hit during the run:** error 40613 on the very first connect attempt (overnight auto-pause wake). Manual retry after 45s succeeded. Logged as a "two distinct cold-start failure classes" entry — the session-2 timeout fix doesn't cover 40613. Retry-on-40613 logic is a small follow-up improvement, flagged for before Phase 3 wraps the script in Airflow.

**Next session (Phase 3 session 1) — Airflow opens:**

- Stand up the Airflow Docker stack (compose file with webserver, scheduler, postgres metadata DB). Local-execute mode is fine for a portfolio project.
- First DAG: wrap `scripts/extract_azure_to_snowflake.py --run-date {{ ds }}` as a single PythonOperator task. Backfill catchup disabled initially; first scheduled run starts at 2014-01-01.
- Optional pre-work for Phase 3 session 1: add retry-on-40613 logic to the extract script so the first scheduled Airflow run doesn't trip on a cold Azure SQL.

---

## Pre-flight check results

| Check                    | Result                                     | Implication                                        |
| ------------------------ | ------------------------------------------ | -------------------------------------------------- |
| RAM                      | 31.7 GB total                              | Full Docker stack supported, no compromises needed |
| Docker Desktop           | ✅ Installed (v29.4.2), WSL 2 backend      | Ready for Phase 3 (Airflow)                        |
| Python                   | ✅ 3.11.9 available                        | Sufficient (need 3.11+)                            |
| Git / GitHub             | ✅ Working, repo created and pushed        | Public repo live                                   |
| Kaggle account           | ✅ Active, phone verified                  | Can use API                                        |
| Kaggle API token         | ✅ kaggle.json in `C:\Users\Phil\.kaggle\` | Ready for scripted download                        |
| Azure subscription       | ✅ Active, Owner role, $0 current spend    | Will use Azure SQL Database from Phase 1           |
| Power BI Service licence | None — Power BI Free Desktop only          | Build in Desktop, screenshots in README            |
| Snowflake                | NOT signed up yet (intentional)            | Sign up in Phase 2 only                            |

---

## Locked decisions

See `PROJECT_PLAN.md` for the full table. Key updates since the original plan:

- **Source database:** Azure SQL Database Serverless General Purpose (NOT Docker locally) — committed in Phase 1
- **Azure budget alert:** $50/month — to set up in Phase 1
- **Ingestion pattern:** Simulated freshness via date-partitioned incremental extraction (Option B). All M5 history loaded once into Azure SQL; each scheduled Airflow run extracts one new date slice. Locked 2026-05-12.
- **Phase ordering:** Airflow stays in Phase 3 (before dbt + Power BI). Decision confirmed 2026-05-12 — matches how production pipelines actually grow.
- **All other locked decisions:** unchanged from `PROJECT_PLAN.md`

---

## Phase 0 deliverables (completed)

- ✅ Folder renamed to `retail-demand-forecasting-project`
- ✅ Foundational docs created: `PROJECT_PLAN.md`, `PROJECT_CONTEXT.md`, `LEARNINGS.md`, `TEACHING_PREFERENCES.md` (copied from Project 1)
- ✅ `README.md` skeleton with architecture diagram, tech stack, project context
- ✅ `.gitignore` covering secrets, data, Python, dbt, Airflow, Docker, IDE artefacts
- ✅ Docker Desktop installed and verified (v29.4.2)
- ✅ Git repo initialised, branch renamed to `main`
- ✅ First commit made with Phase 0 scaffolding (6 files, 773 insertions)
- ✅ Public GitHub repo created at `https://github.com/Pheluciam/retail-demand-forecasting-project`
- ✅ First commit pushed to GitHub `main`
- ✅ Kaggle account active, phone verified, API token (`kaggle.json`) saved to `C:\Users\Phil\.kaggle\`

---

## Phase 1 — full checklist (all complete)

1. ✅ Resource Group + $50 AUD budget alert
2. ✅ Azure SQL Database (Serverless General Purpose Free tier with auto-pause)
3. ✅ Firewall rule for client IP (`115.69.3.187`)
4. ✅ M5 dataset downloaded from Kaggle to `data/raw/`
5. ✅ Python venv + `requirements.txt` installed
6. ✅ Smoke-test pyodbc connection to Azure SQL
7. ✅ 3 raw tables created (`raw.calendar`, `raw.sell_prices`, `raw.sales_train`) — DDL idempotent, PAGE-compressed
8. ✅ Loader script (`scripts/load_m5_to_azure_sql.py`) — pandas + SQLAlchemy + fast_executemany
9. ✅ Overnight bulk load — 3 tables, ~12 hours total
10. ✅ Post-load verification — row counts + schema + eyeball sample rows all OK (`sql/verify/01_phase1_load_verification.sql`)
11. ✅ Documentation closeout — LEARNINGS + PROJECT_CONTEXT + CODE_QUALITY updated

**Overnight-stability power settings reverted on 2026-05-13 morning.** Nothing pending.

---

## Phase 2 progress

**Phase 2 = Snowflake + extraction.** Estimated 2–3 sessions. Session 1 done.

### Session 1 (2026-05-13 afternoon — ✅ DONE)

1. ✅ Snowflake free trial signed up — Standard edition, AWS, `ap-southeast-2` (Sydney), account `ghrcrqs-hw63290`
2. ✅ Provisioned in Snowflake: warehouse `WH_RETAIL` (XS, auto-suspend 60s), database `RETAIL_DB`, schema `RAW`, role `RETAIL_ENGINEER`, all grants, role hierarchy
3. ✅ Snowflake creds in `.env` (password gitignored); `.env.example` updated with non-secret values
4. ✅ `snowflake-connector-python[pandas]>=3.0.0` added to `requirements.txt` and installed (resolved to v4.5.0)
5. ✅ `scripts/smoke_test_snowflake.py` — connector smoke test passing
6. ✅ `sql/snowflake/01_create_raw_tables.sql` — three RAW tables (CALENDAR, SELL_PRICES, SALES_TRAIN) with `loaded_at` audit cols + Melbourne timezone applied
7. ✅ Locked design decision: backfill cutoff at **2014-01-01** (see `LEARNINGS.md`)

### Session 2 (2026-05-13 late afternoon — ✅ DONE)

1. ✅ `scripts/extract_azure_to_snowflake.py` written — date-parameterised, idempotent, ~440 lines incl. comments
2. ✅ Smoke-tested on increasing windows (1 day calendar, idempotent re-run, 1 day all tables, 7 days all tables); 213,430 sales_train rows verified for the 7-day test
3. ✅ Mid-test 9-point audit completed; three real findings logged (`Connection Timeout=` gotcha, scan-cost economics, transient retry behavior) — all addressed or documented in LEARNINGS
4. ✅ LEARNINGS + PROJECT_CONTEXT updated

### Session 3 (2026-05-14 morning — ✅ DONE)

1. ✅ Windows sleep settings → Never for the duration; reverted post-backfill.
2. ✅ 3-year backfill executed in one invocation:
   ```powershell
   python scripts/extract_azure_to_snowflake.py --start-date 2011-01-29 --end-date 2013-12-31
   ```
   **Wall-clock: 27.3 min** (vs 60-90 min predicted, vs 40-hour original fear).
3. ✅ End-to-end parity verified two ways:
   - Script-internal: source count == written count for all three tables.
   - Independent SQL: `sql/snowflake/02_extract_smoke_tests.sql` Section 5 + `sql/verify/02_phase2_extract_verification.sql` — all three tables `OK`.
4. ✅ Documentation updates: `LEARNINGS.md` (3 entries added), `EXTRACT_PIPELINE.md` (new interview walkthrough), `sql/snowflake/02_extract_smoke_tests.sql` (Section 5), `sql/verify/02_phase2_extract_verification.sql` (new file), `PROJECT_CONTEXT.md` (this file).
5. ✅ Git add + commit + push (Phase 2 closeout commit).

**Phase 2 closed.** Phase 3 (Airflow) opens the next session.

### Quick start for Phase 3 session 1 (Airflow)

```powershell
cd C:\Users\Phil\Documents\Claude\Projects\retail-demand-forecasting-project
.\.venv\Scripts\Activate.ps1
# Re-anchor Claude on PROJECT_CONTEXT.md + TEACHING_PREFERENCES.md + LEARNINGS.md
# Verify Docker Desktop is running: docker --version
# Then start building docker-compose.yml for the Airflow stack.
```

---

## Key reference files

- `PROJECT_PLAN.md` — static plan, scope, timeline, locked decisions, risks
- `TEACHING_PREFERENCES.md` — how Phil works with Claude (carry-forward from Project #1, plus SQL CAPS preference and Project 2 pacing notes)
- `LEARNINGS.md` — running journal of lessons learned (populated as we go)
- `LEARNING_ROADMAP.md` — forward-looking learning pathway beyond Project #2 (incl. planned post-Project-#3 six-week Python deep dive)
- `README.md` — public-facing project intro for hiring managers (built up over Phase 6)
- `.gitignore` — files Git should ignore (secrets, data, build artefacts)

---

## Project #1 reference

For carry-forward learnings and patterns:

- `C:\dbt\cdc_nt_gtfs\TEACHING_PREFERENCES.md` (canonical version — kept in sync with our copy)
- `C:\dbt\cdc_nt_gtfs\LEARNINGS.md` (Project #1 lessons)
- `C:\dbt\cdc_nt_gtfs\NEXT_PROJECT.md` (the roadmap that informed this project)

---

## Public GitHub repo

https://github.com/Pheluciam/retail-demand-forecasting-project
