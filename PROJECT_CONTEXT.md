# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Live state of the project. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-14 (Phase 3 session 1 closed — Airflow stack live, first DAG running end-to-end).

---

## Where we are right now

**Current phase:** Phase 3 — session 1 ✅ DONE. Next session opens **Phase 3 session 2 (Airflow polish + scheduled-run observation)**.

**Last action (2026-05-14 — Phase 3 session 1):** Full Airflow stack stood up via Docker Compose, first DAG written and parsing cleanly, manual trigger of two consecutive incremental days (2014-01-01, 2014-01-02) succeeded end-to-end. 56,860 rows moved through the pipeline orchestrated by Airflow (no human in the loop after the trigger). Independent Snowflake-side verification returned six PASS rows.

**Files added this session (Phase 3 session 1):**

- `airflow/Dockerfile` — custom image extending `apache/airflow:2.10.3-python3.11`, layering on Microsoft ODBC Driver 17 + a minimal `requirements-airflow.txt`. Versions single-sourced via ARG above FROM.
- `airflow/docker-compose.yml` — postgres metadata DB + idempotent init + webserver + scheduler. LocalExecutor. `env_file: ../.env` for Azure SQL + Snowflake creds. `../scripts:/opt/airflow/scripts:ro` mount so the DAG can call the existing extract module.
- `airflow/requirements-airflow.txt` — minimal extras (pyodbc, python-dotenv, snowflake-connector-python[pandas]) with no version pins; let Airflow's constraints file decide versions.
- `airflow/dags/m5_daily_extract.py` — first DAG. `@daily`, `start_date=2014-01-01 Australia/Melbourne`, `catchup=False`, `max_active_runs=1`, `retries=2`. Single `@task` wraps `extract_azure_to_snowflake.main()` via `sys.argv` shim. Tags: `m5`, `extract`, `phase3`.
- `airflow/README.md` — boot/shutdown/diagnostics cheatsheet for the stack. Quick-start commands, common gotchas, layout reference.
- `pyrightconfig.json` (project root) — `extraPaths: ["scripts"]` so Pylance resolves the DAG-side `import extract_azure_to_snowflake` against the actual module on the host. Tool-agnostic editor config.
- `sql/verify/03_phase3_dag_extract_verification.sql` — independent Snowflake-side verification of the first two Airflow-orchestrated extracts. Four detailed sections + a Section 5 PASS/FAIL rollup using the CTE pattern.

**Files updated this session:**

- `scripts/extract_azure_to_snowflake.py` — added `wake_azure_sql()` helper for retry-on-40613/40197, wired into `main()` between `connect_azure_sql()` and `connect_snowflake()`. Also added CLI-contract note in the module docstring warning that the DAG depends on `--run-date`.
- `CODE_QUALITY.md` — added new criterion 6 "Dev environment hygiene"; renumbered existing 6→7, 7→8, 8→9, 9→10; "six core checks" → "seven core checks". Triggered by yellow-squigglies-on-DAG-file mid-session.
- `TEACHING_PREFERENCES.md` — mirrored the criterion 6 addition. Plus added an explicit rule about showing code changes inline (with line numbers, file paths, before/after) for code-shaped files but not for doc-shaped files. Refined twice through the session as Phil clarified preferences.
- `LEARNINGS.md` — eight new entries across the Airflow section: stack architecture, custom-image SQLAlchemy/constraints story, Docker-daemon-must-run, code-quality framework gap, Airflow 2.x CLI flag versioning (`-e` not `--logical-date`), `catchup=False` semantics on unpause, CTE-based PASS/FAIL pattern.
- Local `.venv` — `pip install pendulum "apache-airflow==2.10.3" --no-deps` to give Pylance enough to resolve airflow imports without dragging in Windows-incompatible transitive deps.

**Headline outcomes from this session:**

- **First DAG end-to-end working.** `m5_daily_extract` triggered twice via Airflow CLI (`docker compose exec airflow-scheduler airflow dags trigger m5_daily_extract -e <date>`), both runs landed real rows in Snowflake. 2014-01-01: 1 + 25,939 + 30,490 = 56,430 rows. 2014-01-02: same shape (sell_prices shares the fiscal week, so the same 25,939 rows back the second date too).
- **Verification clean.** Independent Snowflake-side SQL (`sql/verify/03_phase3_dag_extract_verification.sql`) returned 6 PASS, 0 FAIL. Both script-internal parity and downstream double-check aligned.
- **The wake helper earned its keep on its first real run.** When the manual smoke test ran in PowerShell after lunch, Azure SQL had auto-paused; `wake_azure_sql` caught 40613, slept 45s, retried, succeeded. Exactly the failure mode predicted in `LEARNINGS` during Phase 2 session 3 — now covered.
- **Code-quality framework grew during the session.** Yellow Pylance squigglies on the freshly-written DAG file revealed the original 9 criteria didn't cover dev-environment hygiene. Added criterion 6 and renumbered the rest. The framework now catches this class of issue going forward.
- **Mid-session pacing refinement.** Phil pushed back on "lots of changes summarised in bullets, hard to follow." `TEACHING_PREFERENCES.md` updated twice to capture an explicit rule for inline code display (path + line numbers + before/after for code-shaped files; description-only for doc-shaped).

**Next session (Phase 3 session 2) — Airflow polish + scheduled-run observation:**

- Toggle DAG back off between sessions OR let the daily schedule walk forward and observe live. If left running, by next session there should be 1-3 additional auto-fired runs in the metadata DB (2026-05-15, 16, 17), which is itself useful as a demo of "Airflow runs by itself."
- Add a downstream Snowflake-side verification task to the DAG. Two-task DAG: `extract_one_day` → `verify_one_day`. The verify task queries Snowflake and confirms the row count matches what the script reported. Closes the loop inside Airflow rather than relying on a manual SQL run.
- Consider `AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS=true` in docker-compose so future manual triggers can use the UI form (with calendar date picker) rather than the CLI. Requires `down`+`up` cycle to take effect.
- Document the run in the README's architecture diagram so the new Airflow section in the public README has a concrete example of an Airflow-orchestrated extract.
- Stretch: VS Code Dev Containers as a Phase 6 polish item — attaches the editor *into* the running Airflow container, eliminating any Windows-host vs Linux-runtime drift. Real-DE-shop pattern, strong interview talking point.

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

## Phase 3 progress

**Phase 3 = Orchestration with Airflow.** Estimated 2–3 sessions. Session 1 done.

### Session 1 (2026-05-14 afternoon — ✅ DONE)

1. ✅ Pre-work: added `wake_azure_sql()` retry helper to `scripts/extract_azure_to_snowflake.py`, covering Azure SQL cold-start error codes 40613 and 40197. 3 attempts × 45s delay. Smoke-tested against a paused DB — caught 40613 on attempt 1, retried, succeeded.
2. ✅ Built Airflow Docker stack: `airflow/Dockerfile` (custom image with msodbcsql17 + minimal requirements pinned to Airflow constraints) + `airflow/docker-compose.yml` (postgres + idempotent init + webserver + scheduler, LocalExecutor, env_file from `../.env`).
3. ✅ Booted the stack — three containers healthy, UI reachable at `localhost:8080` with `airflow`/`airflow` admin login.
4. ✅ Wrote first DAG `m5_daily_extract` using the TaskFlow API (@dag + @task decorators). Calls existing extract script via `sys.argv` shim so the script needs zero changes. Catchup off, max_active_runs=1, retries=2.
5. ✅ Triggered manually for `2014-01-01` and `2014-01-02` via Airflow CLI inside the scheduler container. Both runs landed real rows end-to-end through the orchestrated pipeline.
6. ✅ Verified independently from Snowsight via `sql/verify/03_phase3_dag_extract_verification.sql` — 6 PASS / 0 FAIL using the new CTE-based summary template.

### Mid-session: code-quality framework evolved

- ✅ Yellow Pylance squigglies on the DAG file revealed a gap: original 9 criteria all audited code content, never the dev environment around it. Added criterion 6 "Dev environment hygiene" to `CODE_QUALITY.md` and `TEACHING_PREFERENCES.md`; renumbered the rest (six core checks → seven).
- ✅ Practical fixes for the same gap: `pyrightconfig.json` + `pip install pendulum apache-airflow==2.10.3 --no-deps` to give Pylance enough to resolve DAG imports on Windows without dragging in Airflow's Unix-only transitive deps. Flagged VS Code Dev Containers as a Phase 6 polish improvement.

### Mid-session commit

- ✅ Git commit `d1eee77` — "feat(airflow): Phase 3 session 1 - stack scaffolding + first DAG (pre-trigger)". Pushed to `origin/main`. Captures the stack + DAG before the first trigger fired.

### Session 1 closeout (this commit)

- ✅ Three new LEARNINGS entries: Airflow 2.x CLI flag versioning (`-e` vs `--logical-date`), `catchup=False` unpause semantics, CTE PASS/FAIL pattern.
- ✅ This `PROJECT_CONTEXT.md` updated to reflect Phase 3 session 1 closing.
- ✅ Git commit + push (this commit).

**Phase 3 session 1 closed.** Session 2 opens with Airflow polish: downstream verify task, scheduled-run observation, UI trigger-with-config enabled.

### Quick start for Phase 3 session 2

```powershell
cd C:\Users\Phil\Documents\Claude\Projects\retail-demand-forecasting-project
.\.venv\Scripts\Activate.ps1
cd airflow
docker compose up -d                                    # boot stack if not running
docker compose ps                                       # verify all three healthy
# Re-anchor Claude on PROJECT_CONTEXT.md + TEACHING_PREFERENCES.md + LEARNINGS.md
# Open Airflow UI: http://localhost:8080  (airflow / airflow)
# Check for any auto-fired runs since last session via Grid view.
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
