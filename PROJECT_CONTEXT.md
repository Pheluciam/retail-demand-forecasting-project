# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Live state of the project. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-09.

---

## Where we are right now

**Current phase:** Phase 0 — **COMPLETE** ✅

**Last action:** All Phase 0 setup tasks complete. Repo initialised, first commit pushed to public GitHub at https://github.com/Pheluciam/retail-demand-forecasting-project. Docker, Git, Python, Kaggle credentials all verified and in place. Ready to begin Phase 1.

**Next session starts with:** Phase 1 — provision Azure SQL Database, download M5 data, load into the source database.

---

## Pre-flight check results

| Check | Result | Implication |
|---|---|---|
| RAM | 31.7 GB total | Full Docker stack supported, no compromises needed |
| Docker Desktop | ✅ Installed (v29.4.2), WSL 2 backend | Ready for Phase 3 (Airflow) |
| Python | ✅ 3.11.9 available | Sufficient (need 3.11+) |
| Git / GitHub | ✅ Working, repo created and pushed | Public repo live |
| Kaggle account | ✅ Active, phone verified | Can use API |
| Kaggle API token | ✅ kaggle.json in `C:\Users\Phil\.kaggle\` | Ready for scripted download |
| Azure subscription | ✅ Active, Owner role, $0 current spend | Will use Azure SQL Database from Phase 1 |
| Power BI Service licence | None — Power BI Free Desktop only | Build in Desktop, screenshots in README |
| Snowflake | NOT signed up yet (intentional) | Sign up in Phase 2 only |

---

## Locked decisions

See `PROJECT_PLAN.md` for the full table. Key updates since the original plan:

- **Source database:** Azure SQL Database Serverless General Purpose (NOT Docker locally) — committed in Phase 1
- **Azure budget alert:** $50/month — to set up in Phase 1
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

## Immediate next steps (Phase 1)

1. Sign in to Azure portal, create a Resource Group for this project
2. Set up budget alert at $50/month
3. Provision Azure SQL Database (Serverless General Purpose tier with auto-pause)
4. Configure firewall rule to allow your IP
5. Download M5 dataset from Kaggle (using kaggle CLI)
6. Create Python venv and install required packages (`pyodbc`, `pandas`, `kaggle`, etc.)
7. Load M5 raw CSVs into Azure SQL Database
8. Verify row counts and sample data

Estimated effort for Phase 1: 1–2 sessions.

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
