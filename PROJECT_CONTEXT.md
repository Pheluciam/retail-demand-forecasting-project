# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Live state of the project. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-13 (afternoon — end of Phase 2 session 1).

---

## Where we are right now

**Current phase:** Phase 2 — IN PROGRESS (session 1 of ~3 done)

**Last action (2026-05-13 afternoon — Phase 2 session 1):** Snowflake account stood up end-to-end. Six of nine Phase 2 sub-tasks complete:

1. ✅ Snowflake free trial signed up (Standard edition, AWS, `ap-southeast-2` Sydney; account `ghrcrqs-hw63290`)
2. ✅ Provisioned `WH_RETAIL` (XS, auto-suspend 60s) + `RETAIL_DB.RAW` + `RETAIL_ENGINEER` role + full grants + role hierarchy (`RETAIL_ENGINEER` → `SYSADMIN`)
3. ✅ `.env` + `.env.example` updated with Snowflake config (password gitignored)
4. ✅ `snowflake-connector-python[pandas]` 4.5.0 installed (note: pulled pandas back from 3.0.3 → 2.3.3 — connector hasn't qualified pandas 3.x yet)
5. ✅ `scripts/smoke_test_snowflake.py` written and passing — all six `CURRENT_*()` values resolve correctly
6. ✅ `sql/snowflake/01_create_raw_tables.sql` run — three empty RAW tables in `RETAIL_DB.RAW` with `loaded_at` audit cols + Melbourne timezone applied

**Phase 2 sub-tasks remaining (next session):**

7. ⏳ Write `scripts/extract_azure_to_snowflake.py` — date-parameterised, ~200-300 lines. This is the headline Python work.
8. ⏳ Test extract on calendar → sell_prices → sales_train (small date window first)
9. ⏳ 9-point code-quality audit + LEARNINGS update + git commit

**Files added this session:**

- `sql/snowflake/00_provision_account.sql` — warehouse / db / schema / role / grants / timezone setup
- `sql/snowflake/01_create_raw_tables.sql` — three RAW tables DDL
- `scripts/smoke_test_snowflake.py` — connector smoke test
- `LEARNING_ROADMAP.md` — captures post-Project-#3 6-week Python deep-dive plan

**Files updated this session:**

- `.env` + `.env.example` — Snowflake creds added
- `requirements.txt` — `snowflake-connector-python[pandas]` added
- `PROJECT_CONTEXT.md` (this file)
- `LEARNINGS.md` — Snowflake section populated, new design decision logged

**Next session starts with:** writing `scripts/extract_azure_to_snowflake.py` — the date-parameterised extract job. **Locked decision (made this session):** backfill cutoff at **2014-01-01** (backfill 2011-01-29 → 2013-12-31, then incremental walk 2014-01-01 → 2016-06-19). See `LEARNINGS.md` Design Decisions for the full rationale.

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

### Session 2 (next — extract script)

1. Write `scripts/extract_azure_to_snowflake.py` — date-parameterised from day one (takes `--run-date` arg) per locked decision (simulated freshness). ~200-300 lines.
2. Test extract on `raw.calendar` first (smallest), then sell_prices, then sales_train, with a tiny date window
3. 9-point code-quality audit before sign-off
4. Update LEARNINGS + PROJECT_CONTEXT; git commit + push

### Quick start for the next Phase 2 session

```powershell
cd C:\Users\Phil\Documents\Claude\Projects\retail-demand-forecasting-project
.\.venv\Scripts\Activate.ps1
# Re-anchor Claude on PROJECT_CONTEXT.md + TEACHING_PREFERENCES.md + LEARNINGS.md
# Then: write scripts/extract_azure_to_snowflake.py (Phase 2 sub-task 7)
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
