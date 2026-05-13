# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Live state of the project. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-13 (late afternoon — end of Phase 2 session 2).

---

## Where we are right now

**Current phase:** Phase 2 — IN PROGRESS (sessions 1 + 2 done, session 3 = backfill)

**Last action (2026-05-13 late afternoon — Phase 2 session 2):** `scripts/extract_azure_to_snowflake.py` written, tested end-to-end, and proven idempotent. Eight of nine Phase 2 sub-tasks now complete:

1. ✅ Snowflake free trial signed up
2. ✅ Snowflake account provisioned (warehouse, database, schema, role, grants)
3. ✅ Snowflake creds in `.env`
4. ✅ `snowflake-connector-python[pandas]` 4.5.0 installed
5. ✅ `scripts/smoke_test_snowflake.py` written and passing
6. ✅ `sql/snowflake/01_create_raw_tables.sql` run — three RAW tables ready
7. ✅ **`scripts/extract_azure_to_snowflake.py` written** (~440 lines including comments)
8. ✅ **Smoke-tested end-to-end on increasing windows:**
   - 1 day, calendar only → 1 row, parity OK
   - Re-run for idempotency proof → pre-DELETE removed 1, re-inserted 1, **still 1 row** ✓
   - 1 day, all three tables → 30,490 sales_train rows, parity OK
   - **7 days, all three tables → 213,430 sales_train rows, parity OK in 121 sec**
   - Transient HTTP retry mid-PUT recovered automatically by Snowflake connector
9. ⏳ Run actual 3-year backfill + git commit + push (Phase 2 session 3, next session)

**Files added this session (Phase 2 session 2):**

- `scripts/extract_azure_to_snowflake.py` — date-parameterised Azure SQL → Snowflake extract job. Single CLI tool, two modes: `--run-date YYYY-MM-DD` (incremental) or `--start-date X --end-date Y` (backfill).

**Files updated this session:**

- `LEARNINGS.md` — added (a) `Connection Timeout=` ODBC gotcha + fix, (b) `write_pandas` throughput numbers, (c) Snowflake connector transient retry observation, (d) fixed-scan-cost design decision for backfill timing
- `PROJECT_CONTEXT.md` (this file)

**Key technical findings from this session:**

- **`Connection Timeout=90` in the ODBC connection string was silently ignored.** Fix: pass `connect_args={"timeout": 90}` to SQLAlchemy `create_engine` instead. Phase 1's `load_m5_to_azure_sql.py` has the same latent flaw — flagged as a small side-quest. See LEARNINGS "Mistakes & diagnoses".
- **`write_pandas` throughput: ~14,000-15,000 rows/sec** sustained on 100k-row chunks for `sales_train`. Much faster than Phase 1's ~1,500 rows/sec write to Azure SQL — different architecture, not different language.
- **Sales_train table-scan cost is fixed per query**, not per row. 7-day extract was *faster* than 1-day extract. Implication: 3-year backfill will be **~60-90 minutes**, not 40 hours as initially feared. See LEARNINGS "Design decisions".

**Next session (Phase 2 session 3) starts with:**

- Reset overnight power settings (sleep/screen-off → Never) — same checklist as Phase 1 overnight load.
- Kick off the 3-year backfill in one invocation:
  ```powershell
  python scripts/extract_azure_to_snowflake.py --start-date 2011-01-29 --end-date 2013-12-31
  ```
- While it runs (~60-90 min), do the final 9-point audit pass + finalize LEARNINGS + git add + commit + push.
- Wraps up Phase 2 cleanly; Phase 3 (Airflow) starts the session after.

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

### Session 3 (next — backfill + Phase 2 closeout)

1. Reset overnight-stability power settings (Never sleep, Never screen-off, lid close → Do nothing) per Phase 1 carry-forward.
2. Run the actual 3-year backfill in one invocation (~60-90 min):
   ```powershell
   python scripts/extract_azure_to_snowflake.py --start-date 2011-01-29 --end-date 2013-12-31
   ```
3. Post-backfill verification: source-vs-destination row counts for all three tables.
4. Git add + commit + push (extract script + LEARNINGS + PROJECT_CONTEXT updates from session 2).
5. Phase 2 done. Phase 3 (Airflow) opens the session after.

### Quick start for Phase 2 session 3

```powershell
cd C:\Users\Phil\Documents\Claude\Projects\retail-demand-forecasting-project
.\.venv\Scripts\Activate.ps1
# Re-anchor Claude on PROJECT_CONTEXT.md + TEACHING_PREFERENCES.md + LEARNINGS.md
# Reset Windows power settings → Never
# Then: backfill 2011-01-29 → 2013-12-31 (one PowerShell invocation, ~60-90 min)
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
