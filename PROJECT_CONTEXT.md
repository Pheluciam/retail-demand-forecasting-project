# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Live state of the project. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-12.

---

## Where we are right now

**Current phase:** Phase 1 — ✅ **COMPLETE** (2026-05-13)

**Last action (2026-05-13 morning):** Verified the overnight bulk load completed successfully. All 3 raw tables landed with correct row counts:

| Table | Row count | Status |
|---|---|---|
| `raw.calendar` | 1,969 | ✅ verified |
| `raw.sell_prices` | 6,841,121 | ✅ verified |
| `raw.sales_train` | 59,181,090 | ✅ verified |

Schema verification (column counts) and eyeball checks on sample rows all passed via `sql/verify/01_phase1_load_verification.sql` (new file, 5-section verification suite).

**Final runtime stats:** total elapsed ~12.2 hours.
- calendar: ~5 sec
- sell_prices: 73.1 min (avg 1,560 rows/sec)
- sales_train: 659.6 min (~11 h, avg 1,495 rows/sec — Free Serverless 2 vCores throughput cap)

**One bookkeeping note from the run:** the script's `EXPECTED_ROWS["sales_train"]` constant had an off-by-1000 arithmetic error (set to 59,180,090; correct value 59,181,090). Verification correctly raised a `MISMATCH`/`ValueError` — but against the wrong baseline. Constant since corrected in source; lesson captured in `LEARNINGS.md` under *Mistakes & diagnoses*.

**Next session starts with:** Phase 2 — Snowflake signup + Python extract job (Azure SQL → Snowflake RAW).

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

## Phase 2 starting point

**Phase 2 = Snowflake + extraction.** Estimated 2–3 sessions.

### Pre-Phase-2 reminder (read before starting next session)

- **DO NOT sign up for Snowflake yet outside a Phase 2 session.** The free trial is a 30-day clock that starts on signup. Sign up *first thing* when Phase 2 starts, then build immediately so the clock counts toward useful work, not setup downtime.

### Phase 2 session 1 plan (next session)

1. Sign up for Snowflake free trial → `signup.snowflake.com`
   - Pick **AWS** as the cloud, **Standard** edition, region closest to AU East
2. In Snowflake, provision: warehouse `WH_RETAIL` (XS), database `RETAIL_DB`, schema `RAW`, role `RETAIL_ENGINEER`
3. Add Snowflake connection details to `.env` (the placeholders already exist in `.env.example`)
4. Add `snowflake-connector-python` to `requirements.txt` and install
5. Write `scripts/extract_azure_to_snowflake.py` — date-parameterised from day one (takes `--run-date` arg) per locked decision (simulated freshness)
6. Test extract on `raw.calendar` first (smallest), then sell_prices, then sales_train

### Quick start for the Phase 2 session

```powershell
cd C:\Users\Phil\Documents\Claude\Projects\retail-demand-forecasting-project
.\.venv\Scripts\Activate.ps1
# Re-anchor Claude on PROJECT_CONTEXT.md + TEACHING_PREFERENCES.md + LEARNINGS.md
# Then start Phase 2 step 1 — Snowflake signup
```

---

## Key reference files

- `PROJECT_PLAN.md` — static plan, scope, timeline, locked decisions, risks
- `TEACHING_PREFERENCES.md` — how Phil works with Claude (carry-forward from Project #1, plus SQL CAPS preference and Project 2 pacing notes)
- `LEARNINGS.md` — running journal of lessons learned (populated as we go)
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
