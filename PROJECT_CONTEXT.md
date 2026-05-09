# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Live state of the project. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-09.

---

## Where we are right now

**Current phase:** Phase 0 — Setup (in progress)

**Last action:** Pre-flight checks complete. Folder renamed to `retail-demand-forecasting-project`.
Project files scaffolded (`PROJECT_PLAN.md`, `TEACHING_PREFERENCES.md`, `LEARNINGS.md`,
this file). About to initialise Git repo and create remaining scaffolding.

---

## Pre-flight check results

| Check | Result | Implication |
|---|---|---|
| RAM | 31.7 GB total | Full Docker stack supported, no compromises needed |
| Disk space | (to confirm — need ~30 GB free) | |
| Docker Desktop | (to confirm installed) | |
| VS Code | (assumed installed from Project #1) | |
| Python 3.11+ | (to confirm) | |
| Git / GitHub | (carryover from Project #1) | |
| Kaggle account | (to set up if not already) | Need before downloading M5 |
| Kaggle API token | (to set up if not already) | For scripted download |
| Azure subscription | Active, Owner role, $0 current spend | Will use Azure SQL Database from Phase 1 |
| Power BI Service licence | None — Power BI Free Desktop only | Build in Desktop, screenshots in README |
| Snowflake | NOT signed up yet (intentional) | Sign up in Phase 2 only |

---

## Locked decisions

See `PROJECT_PLAN.md` for the full table. Key updates since the original plan:

- **Source database:** Azure SQL Database Serverless General Purpose (NOT Docker locally) — committed in Phase 1
- **Azure budget alert:** $50/month — to set up in Phase 1
- **All other locked decisions:** unchanged from `PROJECT_PLAN.md`

---

## Immediate next steps

1. Confirm remaining pre-flight items (Docker installed, Python version, Kaggle account)
2. Initialise Git repo and create first commit (empty repo + scaffolding)
3. Create remaining Phase 0 files (`README.md` skeleton, `.gitignore`, conventions doc)
4. Push to public GitHub repo
5. Move into Phase 1 — provision Azure SQL Database and download M5

---

## Key reference files

- `PROJECT_PLAN.md` — static plan, scope, timeline, locked decisions, risks
- `TEACHING_PREFERENCES.md` — how Phil works with Claude (carry-forward from Project #1)
- `LEARNINGS.md` — running journal of lessons learned (populated as we go)
- `README.md` — public-facing project intro for hiring managers (built up over Phase 6)

---

## Project #1 reference

For carry-forward learnings and patterns:

- `C:\dbt\cdc_nt_gtfs\TEACHING_PREFERENCES.md` (canonical version — same as our copy)
- `C:\dbt\cdc_nt_gtfs\LEARNINGS.md` (Project #1 lessons)
- `C:\dbt\cdc_nt_gtfs\NEXT_PROJECT.md` (the roadmap that informed this project)
