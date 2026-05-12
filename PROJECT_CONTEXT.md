# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Live state of the project. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-12.

---

## Where we are right now

**Current phase:** Phase 1 — **IN PROGRESS** 🟡 (first half complete)

**Last action (2026-05-12):** Azure infrastructure provisioned end-to-end on the Azure Free SQL Database offer. Resource Group, $50 AUD budget alert, Azure SQL Database Serverless (Free tier — 100k vCore-sec + 32 GB storage free for life of subscription, with overage billing disabled), firewall rule for client IP, and connection verified via portal Query Editor (`SELECT @@VERSION` returned `Microsoft SQL Azure 12.0.2000.8`). M5 dataset downloaded from Kaggle to `data/raw/` — all 5 CSVs present (~450 MB uncompressed). Python venv set up with `kaggle`, `pyodbc`, `pandas`, `python-dotenv`, `sqlalchemy` in `requirements.txt`. Secrets in local `.env` (gitignored); template in `.env.example` (committed).

**Next session starts with:** Phase 1 second half — bulk-load the 5 M5 CSVs from `data/raw/` into Azure SQL Database. Wide-format sales tables go in as-is (unpivot happens in dbt staging later, per locked decision).

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

## Immediate next steps (Phase 1, second half)

1. ✅ ~~Sign in to Azure portal, create a Resource Group for this project~~
2. ✅ ~~Set up budget alert at $50/month~~ (set at $50 AUD)
3. ✅ ~~Provision Azure SQL Database (Serverless General Purpose tier with auto-pause)~~ — on Free offer
4. ✅ ~~Configure firewall rule to allow your IP~~ — handled inline during provisioning; current IP `115.69.3.187` whitelisted
5. ✅ ~~Download M5 dataset from Kaggle (using kaggle CLI)~~
6. ✅ ~~Create Python venv and install required packages~~ — `.venv` created with `kaggle` installed; full `requirements.txt` to be installed at start of next session via `pip install -r requirements.txt`
7. ⬜ **Load M5 raw CSVs into Azure SQL Database** ← next session starts here
8. ⬜ Verify row counts and sample data

### Quick start for next session

```powershell
cd C:\Users\Phil\Documents\Claude\Projects\retail-demand-forecasting-project
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Then write a Python script using `pyodbc` + `pandas` to read each CSV from `data/raw/` and bulk-insert into Azure SQL. Wide-format sales tables go in as-is. Connection details are in `.env`.

Estimated effort for Phase 1 second half: 1 session.

### Known issue to fix at session start

VS Code's default Python interpreter path still points to the deleted Project #1 venv (`C:\Users\Phil\Documents\CDC_NT_ETL\.venv`). Fix by `Ctrl+Shift+P` → `Python: Select Interpreter` → pick `.venv` inside this project.

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
