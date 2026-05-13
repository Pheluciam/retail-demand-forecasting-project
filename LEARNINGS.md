# LEARNINGS.md — Retail Demand & Forecasting Pipeline

> A running journal of what I'm learning on Project #2.
> First entry: 2026-05-09.

This is my second data engineering project, building on what I learned in Project #1
(CDC NT Transport). The point of this document isn't to look polished. It's to capture
the real moments where something clicked, broke, or made me rethink an assumption,
so I can refer back to it in interviews and on future projects.

---

## Project summary

End-to-end data engineering portfolio project building a production-grade retail
demand-planning analytics platform. Real Walmart sales data (M5 Forecasting dataset)
is ingested from Azure SQL Database into Snowflake via scheduled Airflow jobs,
transformed through a partitioned star schema with dedicated marts using dbt,
and surfaced as a five-page Power BI dashboard for an operations / S&OP audience.

Headline focus: **orchestration**. Pipeline runs end-to-end on a schedule with proper
failure handling, tests, and CI — not button-pressed like Project #1.

---

## Technical learnings

> Sections below will fill in as work progresses. Each entry should capture what
> happened, what was new, and what I'd do differently. Project #1 examples for
> reference are in `C:\dbt\cdc_nt_gtfs\LEARNINGS.md`.

### Azure SQL Database

**Provisioning (2026-05-12 session)**

- **"Azure SQL" in Marketplace is a hub, not a product.** It splits into SQL databases, Managed Instance, SQL VMs. We want **SQL databases** (Single database). The Azure UI also pushes **Hyperscale** as the headline option — that's a different (more expensive) tier, NOT what we want. Plain General Purpose Serverless is correct for a project this size.
- **Free Azure SQL Database offer exists and is excellent.** 100,000 vCore-seconds + 32 GB data + 32 GB backup free **per month for the lifetime of the subscription**. One free database per subscription. Critical safety: when free limits are hit, you can configure "auto-pause until next month" with **Overage billing: Disabled**, meaning zero risk of unexpected charges. This is dramatically better than the paid path I'd planned for.
- **Logical server vs database.** Two distinct concepts. The **server** is the security/firewall boundary with a globally unique public hostname (`*.database.windows.net`); the **database** lives inside it. Server names must be globally unique across all Azure customers. Used `sql-retail-demand-fc-phm` (phm suffix = initials).
- **Region — Australia East is the AU primary.** Microsoft puts new services there first; Australia Southeast (Melbourne) is the paired DR region with thinner service coverage. Free offer was available in Australia East.

**Firewall**

- During provisioning, the Networking tab has an **"Add current client IP address"** toggle — this creates the firewall rule for you. Public IP captured this session: `115.69.3.187`. Will need to add new rules when working from other networks (mobile hotspot, etc.).
- **"Allow Azure services and resources to access this server" = Yes** allows other Azure services (Azure Functions, Logic Apps, etc.) to connect. Needed if we later integrate with anything Azure-side.

**Authentication**

- **SQL authentication** picked over Microsoft Entra. Reason: our Python scripts (Phase 2 onwards) need a username/password pair to connect. Entra would require setting up an Entra admin on the server and using token-based auth in Python — extra complexity for no portfolio benefit. SQL auth with `sqladmin` + strong password is the right call.
- Admin password must satisfy 3-of-4 complexity (upper / lower / digit / symbol) and 8–128 chars.

**Cost controls**

- Set up a **Resource Group-scoped budget** at $50 AUD before provisioning anything. Budgets are alerts only (not hard caps) — Azure has no true spending hard cap on pay-as-you-go subscriptions.
- For the Free offer, the practical hard cap is "Overage billing: Disabled" — DB pauses, no charges.
- Budget thresholds set: 50%, 80%, 100% Actual + 100% Forecasted. Forecasted is the early-warning alert that catches runaway spend before it actually hits the cap.

**Connection testing**

- **Portal's Query editor (preview)** is excellent for the first connection sanity check — browser-based, no client install. Sign in with SQL auth (`sqladmin` + password), paste `SELECT @@VERSION;`, hit Run. Result confirmed Azure SQL 12.0.2000.8.
- For Phase 2 onwards we'll switch to Azure Data Studio or VS Code's mssql extension for richer querying.

**Secrets management pattern**

- Created `.env` (gitignored) holding real secrets + `.env.example` (committed) as a template. Loaded in Python via `python-dotenv` → `os.getenv()`. Same pattern will extend to Snowflake creds in Phase 2 and Kaggle in any scripted download.
- ⚠️ **Slip this session:** Claude echoed Phil's real password back in a chat message. The password is still valid; risk is low since the transcript is between Phil and Claude (not public), but a clean fix is to rotate the password in Azure portal and update `.env`.

**Auto-pause behaviour (2026-05-12 session)**

- Free Serverless databases **auto-pause after ~1 hour of inactivity** and the cold-start wake takes 30–60 seconds. Default pyodbc `Connection Timeout=30` is too short → got `08001 TCP Provider: Timeout error [258]` despite firewall being correct.
- Fix: bumped `Connection Timeout=90` in all connection strings. First connect of each session is slow; subsequent connects within the active hour are fast. This will matter again in Phase 2/3 (Airflow DAG cold-starts) — bake the 90s into shared connection helpers from day one.
- Diagnostic learned: `Test-NetConnection <host> -Port 1433` cleanly distinguishes firewall/network problems (TCP fails) from auto-pause/login-layer problems (TCP succeeds, login times out).

**PAGE compression on raw tables (2026-05-12)**

- Free Serverless gives 32 GB storage. The `raw.sales_train` table (~59M rows after unpivot) would have eaten ~9 GB uncompressed (NVARCHAR uses 2 bytes/char). Adding `WITH (DATA_COMPRESSION = PAGE)` to the `CREATE TABLE` typically yields 50–70% savings — meaningful headroom on the Free tier.
- Trade-off: marginally more CPU on write, _faster_ reads (less I/O), no query-side complexity. No reason not to use it on any raw table over a few million rows. Skipped on `calendar` (1,969 rows — overhead dwarfs savings).

**SQL Server 1024-column limit (2026-05-12)**

- Azure SQL has a hard limit of 1024 columns per table. M5's wide sales tables (1947 / 1919 cols) exceed this. Original plan was "load wide, unpivot in dbt staging" — locked decision from Phase 0. Had to be revised in Phase 1: **unpivot during the Python load** using `pandas.melt` before insert.
- General rule: column-count and row-count constraints of the **specific** destination dialect must be checked before locking source-shape decisions. Wide tables that fit Snowflake (no practical column limit for our scale) don't necessarily fit SQL Server.

**Code-quality checklist (2026-05-12)**

- Established a 9-point code-quality audit (currency, compactness, resource efficiency, security, workflow consistency, upstream/downstream contract, idempotency, pre/post-action verification, observable progress). Lives in `TEACHING_PREFERENCES.md` — applied to every non-trivial script from this session onwards. First scripts audited: `smoke_test_azure_sql.py`, `01_create_raw_tables.sql`, `create_raw_tables.py`. Public-facing version at `CODE_QUALITY.md` (linked from README).

**Bulk load throughput on Free Serverless (2026-05-12 → 2026-05-13)**

- **Measured throughput:** ~1,500 rows/sec sustained on Azure SQL Free Serverless (2 vCores) via `pandas.to_sql` + `fast_executemany`. Significantly below my pre-load 10–20k rows/sec estimate. Paid Standard tiers (S2/S3) reportedly hit 30–50k rows/sec on the same pattern.
- **End-to-end load times (sequential, in order loaded):**
  - `calendar` (1,969 rows): ~5 sec
  - `sell_prices` (6,841,121 rows): **73.1 min**
  - `sales_train` (59,181,090 rows): **659.6 min** (~11 hours)
  - **Total: ~12.2 hours**
- **Cost (vCore-seconds on Free tier):** approx 87,900 of monthly 100,000 quota consumed by this single load. Hit ~88% of monthly budget in one shot. No issue for Phase 2 (daily extracts are ~minutes of compute) but a useful data point for sizing future bulk operations.
- **Implication for Phase 2:** Snowflake's `COPY INTO` from S3/blob is orders of magnitude faster than row-by-row INSERTs. The Azure SQL → Snowflake extract should be much faster than this initial CSV → Azure SQL load.

**Sleep schedule discipline (2026-05-12 → 2026-05-13)**

- Long-running scripts on consumer-hardware need active OS-level defences: screen-off and sleep both `Never`, lid close `Do nothing`, Windows Update paused. Wi-Fi adapter power management is a separate hidden setting on Windows 11 (often missing from Power Options on Modern Standby devices — accessed via PowerShell `powercfg -attributes SUB_WIRELESSPOWER ... -ATTRIB_HIDE` if needed).
- Carry-forward: write a one-shot **overnight-stability checklist** as a portable artefact, applies to any Project #3 long-running batch.

### Snowflake

**Signup choices (2026-05-13)**

- **"AI Data Cloud — For Enterprise"** vs **"Cortex Code CLI — For Developers"**: different *products*, not different tiers. AI Data Cloud is the standard data warehouse (what we want); Cortex Code CLI is Snowflake's AI coding agent. Don't conflate.
- **"For Enterprise"** (marketing label on the AI Data Cloud button) is NOT the same as **Enterprise edition** (pricing tier). Edition is picked on page 2/2 — chose **Standard**, cheapest tier with everything we need.
- **Cloud provider (AWS / Azure / GCP) doesn't matter** for use cases where data flows via the Python connector. Picked AWS because (a) Snowflake started there in 2014 — most mature; (b) every tutorial / Stack Overflow example uses AWS; (c) cross-cloud transfer is trivial at our volume (~3-5 GB compressed).
- **Region matters for compute location, not timezone.** Picked `ap-southeast-2` (Sydney) — closest to Azure SQL Australia East. AWS and Azure Sydney regions sit in the same physical datacentres anyway.
- **Username convention:** AD-style short identifier (`pheluciam`), not the email address. Email contains `@` and `.` — both special characters in Snowflake identifiers requiring double-quoting in every `GRANT`. Snowflake stores usernames as uppercase regardless of input case.

**Role + permission hierarchy (2026-05-13)**

- **Never use ACCOUNTADMIN for day-to-day work.** Standard pattern: create a dedicated project role (`RETAIL_ENGINEER`), grant it the specific privileges it needs, switch into it for all real work. ACCOUNTADMIN is the equivalent of `root` / `sa` — admin operations only.
- **`GRANT ... ON FUTURE TABLES IN SCHEMA ...`** is critical for any schema where new tables will be created later. Without it, every new table needs its own explicit grant. Pure quality-of-life win.
- **Privilege chain:** USAGE needed at every level (warehouse → database → schema) for a role to reach a table. Forgetting USAGE on schema = "object does not exist or not authorised" errors that are easy to misread.
- **Role hierarchy via `GRANT ROLE RETAIL_ENGINEER TO ROLE SYSADMIN`** — Snowflake's recommended pattern. Lets SYSADMIN also assume the project role without needing ACCOUNTADMIN.

**Timezone gotcha (2026-05-13)**

- **`TIMESTAMP_NTZ` = "No Time Zone"**, NOT New Zealand! Easy misread. Three variants: NTZ (wall clock, no tz), LTZ (stored as UTC, displayed in session tz), TZ (with explicit offset).
- **Region ≠ timezone.** Region = where Snowflake's servers physically run. Timezone = a *display* setting on the user/session. Default timezone on new accounts is `America/Los_Angeles` — confusing for non-US users.
- **Fix:** `ALTER USER <name> SET TIMEZONE = 'Australia/Melbourne'` (persistent, affects all future sessions) + `ALTER SESSION SET TIMEZONE = 'Australia/Melbourne'` (immediate, current session).
- **`(9)` after `TIMESTAMP_NTZ`** = fractional-second precision (9 digits = nanoseconds). Snowflake default.
- **Sydney and Melbourne share timezone** (`Australia/Sydney` / `Australia/Melbourne` interchangeable — same offset, same DST rules). AEST = UTC+10, AEDT = UTC+11. Australian DST: first Sunday October → first Sunday April.

**Warehouse economics (2026-05-13)**

- **`AUTO_SUSPEND = 60` + `AUTO_RESUME = TRUE`** on an XS warehouse means near-zero idle cost — wakes in ~1-2 sec on next query. Significantly faster wake than Azure SQL Free Serverless (30-60s), because Snowflake architecture separates compute from storage and the storage is always live.
- **`INITIALLY_SUSPENDED = TRUE`** on `CREATE WAREHOUSE` = zero credit burn between provisioning and first real query. Default is the opposite — worth setting explicitly.
- **XS = 1 credit/hour while running.** Trial includes $400 credits / 30 days — plenty for a portfolio project at this scale.

**DDL differences vs SQL Server (2026-05-13)**

- **`CREATE OR REPLACE TABLE`** = Snowflake's atomic equivalent of "drop if exists, then create". One statement, no race condition. *Destructive* — wipes data.
- **No `DATA_COMPRESSION = PAGE` needed** — Snowflake auto-compresses everything via micro-partitions (Zstd by default). The entire SQL Server compression DDL story disappears.
- **Column-level `COMMENT '...'`** is supported and useful. Living documentation that shows up in `INFORMATION_SCHEMA.COLUMNS` and Snowsight's table viewer.
- **No `GO` batch separator.** Snowflake parses statement-by-statement; just separate with `;`.
- **Identifier case:** unquoted identifiers stored as UPPERCASE (queries case-insensitive). Quoted identifiers preserve case. For RAW tables, unquoted snake_case is simplest.
- **Audit pattern:** `loaded_at TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() NOT NULL` on every RAW table. Cheap, valuable for Phase 3 "did the pipeline run today?" health checks.

**Clustering keys — when NOT to cluster (2026-05-13)**

- Considered clustering `sales_train` on the `d` column (`'d_1'`..`'d_1941'`) for date-range query speed. **Skipped** — lexicographic order on a text column with variable-width numbers (`d_1, d_10, d_100, ..., d_11`) doesn't match date order. Clustering wouldn't help date-range filters.
- **Correct place to add clustering:** dbt staging layer (Phase 4), where we'll derive a real `sale_date DATE` column by joining `raw.sales_train.d` → `raw.calendar.d`. *That* table can be clustered on the real DATE.
- General principle: cluster on the column you'll actually filter on in the form it's stored, not a proxy that has lookup overhead.

**Connector specifics (2026-05-13)**

- **`snowflake-connector-python[pandas]`** — the `[pandas]` extra pulls in `pyarrow` and enables `write_pandas()`, the recommended bulk-load function (uses PUT to internal stage + COPY INTO under the hood). Without `[pandas]` you'd be doing row-by-row INSERTs — orders of magnitude slower.
- **Dependency drift:** installing `snowflake-connector-python` (resolved to v4.5.0) downgraded pandas from 3.0.3 → 2.3.3. Connector hasn't qualified pandas 3.x yet. `requirements.txt` uses minimum-version pinning only at this stage; when Phase 3 is stable, generate a `requirements-lock.txt` via `pip freeze`.
- **`login_timeout`** and **`network_timeout`** — set explicitly on connections (mirrors the defensive 90s timeouts on Azure SQL after the auto-pause learning). Cold connections may take longer than the default.

**Mental model: three execution locations (2026-05-13)**

Pinning this because confusion crept in mid-session:

| Location | What lives there | What you do there |
|---|---|---|
| **Disk / VS Code** (`sql/snowflake/*.sql`) | Source-of-truth SQL files, version-controlled | Author + edit SQL files |
| **Snowsight worksheets** | Web UI tabs where SQL actually executes | **Run** SQL — the only place SQL touches Snowflake |
| **PowerShell** | Python runtime, pip, Git commands | Run Python scripts (smoke test, extract); never SQL DDL |

Disk file existing ≠ SQL has been run. The two must be reconciled: write to disk → copy → paste into Snowsight worksheet → Run All.

**Worksheet naming convention in Snowsight (2026-05-13)**

- **Numbered worksheets** (`00_provision_account.sql`, `01_create_raw_tables.sql`) mirror the canonical setup-script sequence on disk. A fresh installer would run these in order.
- **Non-numbered worksheets** (`timezone_setup.sql`) are one-off fix-ups applied to an already-provisioned account. Won't be re-run.

### Airflow

_(to be populated during Phase 3 — Docker compose stack, DAG patterns, scheduling,
failure handling, secrets management)_

### dbt (advanced from Project #1)

_(to be populated during Phase 4 — incremental models, partitioning, dbt_utils,
tests, marts layering)_

### Power BI (advanced from Project #1)

_(to be populated during Phase 5 — explicit DAX measures, cross-page slicers,
drill-throughs, format painter, themes)_

### Docker

_(to be populated as encountered — containerisation patterns, docker-compose,
networking between containers)_

### Git / GitHub Actions

_(to be populated as encountered — branching, PRs, CI workflows, sqlfluff lint)_

---

## Mistakes & diagnoses

> Each entry: Symptom → Diagnosis → Fix → What this taught me.
> Capture mid-project, not just at end. Project #1 had ~6 of these — this section
> is where future-me looks first when something goes wrong.

### 2026-05-12 / 2026-05-13 — Verified the shape, not the product

**Symptom:** Overnight bulk load script ran cleanly for 11 hours, then exited with `ValueError: Row count mismatch for raw.sales_train: got 59,181,090, expected 59,180,090` at the very end. Looked like a load failure when first seen in the morning terminal.

**Diagnosis:** Data was correct. The script's `EXPECTED_ROWS["sales_train"]` constant had an off-by-1000 arithmetic error: `30,490 series × 1,941 day columns = 59,181,090`, not the 59,180,090 written in the constant. The verification function correctly compared `actual != expected` and raised — exactly as designed. The _expected value itself_ was wrong.

**Fix:** Updated `EXPECTED_ROWS["sales_train"]` to 59,181,090 in `scripts/load_m5_to_azure_sql.py`. Confirmed actual data via manual `SELECT COUNT_BIG(*)` in Azure Query editor (matched 59,181,090). No re-load needed.

**What this taught me:** Verifying the _shape_ of an arithmetic operation ("30,490 rows × 1,941 day columns") is not the same as verifying the _product_. The dimensions were checked correctly (CSV inspection confirmed 30,490 rows and 1,941 day columns), but the multiplication itself was wrong by 1,000 and never independently recomputed — writing "30,490 × 1,941" makes the answer feel obvious enough not to double-check.

**Going forward:**

- When a magic number guards verification, **compute it via two independent routes** (e.g., Python arithmetic AND a `SELECT 30490 * 1941` directly in SQL).
- Better still — **derive expected values from runtime measurements** rather than hardcoding. The loader could compute `len(df_long)` at melt-time and use that as the verification baseline. Hardcoded magic numbers are a known anti-pattern in test/verification code; this is exactly the failure mode they cause.
- Carry-forward to Project #3.

---

## Design decisions

> Each entry: what was considered, what was chosen, what was the trade-off accepted.
> Particularly important for: dbt-vs-DAX-vs-marts calls, partitioning strategy,
> incremental model design, surrogate key approach.

### 2026-05-12 — Simulated freshness via date-partitioned extraction (Option B)

**Considered:**

- Option A: Load all 6 years of M5 into Azure SQL once, have Airflow run nightly over the full set. Honest about static data in the README.
- Option B: Same one-time bulk load into Azure SQL, but the Airflow DAG extracts ONE new date slice per scheduled run, advancing through M5 history as if it were a live source.

**Chosen:** Option B.

**Trade-off accepted:** Slightly more complex extract script (must accept a `run_date` parameter and filter `WHERE sale_date BETWEEN data_interval_start AND data_interval_end`) in exchange for a dramatically more credible orchestration story. Incremental dbt models, dbt tests, and failure alerts all have something _real_ to fire on — each Airflow run actually processes new rows, instead of looping over the same static set every night.

**Why this matters for the portfolio:** the headline of Project #2 is orchestration. Option A reduces the schedule to theatre. Option B makes "runs daily, picks up new data, transforms, tests, alerts on failure" a true statement.

### 2026-05-12 — Wide-to-long unpivot moved from dbt staging to Python load

**Considered:** Keep the locked Phase 0 decision — load M5 sales wide-as-is into Azure SQL, do the unpivot in dbt staging downstream.

**Forced re-decision:** Azure SQL's 1024-column-per-table hard limit means M5's wide sales tables (1947 / 1919 columns) cannot physically be loaded wide. Three options considered:

1. **Unpivot in Python** during the load step using `pandas.melt`. Long table lands directly in `raw.sales_train`.
2. **Sparse columns** (allow up to 30,000 cols). Preserves the original plan but introduces an unusual feature, hurts query performance, and makes the dbt staging unpivot awkward over 1900+ columns.
3. **Split wide tables** into chunks of ~960 cols each. Ugly, fragmented downstream.

**Chosen:** Option 1 — unpivot in Python.

**Trade-off accepted:** Loses the "raw layer = 1:1 with source CSV shape" purity, in exchange for not fighting the database engine. dbt staging now does cleaning, casting, and renaming — not shape transformation. Load time roughly 2-3× longer (10-30 minutes for full sales table) but no other compromises.

**General rule learned:** column-count limits of the _specific_ destination engine must be verified before locking source-shape decisions. The original plan would have worked on Snowflake or Postgres but not SQL Server. Project #3 carry-forward.

### 2026-05-12 — Drop `sales_train_validation`, keep only `sales_train_evaluation`

**Considered:** Load both wide sales CSVs (validation + evaluation) per the original "all 5 M5 files" plan.

**Chosen:** Load only `sales_train_evaluation`. Skip `sales_train_validation`.

**Trade-off accepted:** Slightly diverges from the Kaggle competition convention, but `evaluation` is a strict superset — same 30,490 series, plus 28 extra days at the end. Loading both would have produced 58M duplicate rows for zero analytical gain.

**Final raw table count:** 3 (calendar, sell_prices, sales_train), not the "6 raw tables" mentioned loosely in early plan drafts. Also dropped `sample_submission.csv` as out-of-scope (competition submission format, irrelevant to the demand-planning pipeline).

### 2026-05-12 — Airflow stays in Phase 3 (before dbt and Power BI)

**Considered:** Build dbt and Power BI manually first (Phases 3 + 4), then wrap everything in Airflow at the end.

**Chosen:** Keep the plan's ordering — Airflow in Phase 3, dbt in Phase 4, Power BI in Phase 5.

**Trade-off accepted:** Airflow lands before there's a "full" pipeline to schedule — but by end of Phase 2 there's already a working Python extract script, which is exactly what gets wrapped in the first DAG. New layers (dbt, then Power BI refresh) bolt onto the existing DAG as additional tasks. This matches how production pipelines actually grow: orchestration is built early and small, then extended, not bolted on at the end.

**Why this matters:** the headline deliverable shouldn't be the last thing built. If Airflow goes last and the project runs out of energy, the portfolio piece loses its differentiator from Project #1.

### 2026-05-13 — Backfill/incremental cutoff at 2014-01-01

**Considered:** With Option B (simulated freshness via date-partitioned extraction) locked the previous day, the remaining question was: where does the *backfill* end and the *incremental walk* begin? Three options weighed:

1. **Cutoff at 2014-01-01** — backfill 2011-01-29 → 2013-12-31 (~3 years, ~33M sales rows). Incremental window 2014-01-01 → 2016-06-19 (~2.5 years, ~26M rows).
2. **Cutoff at 2015-01-01** — heavier backfill (~4 years, ~43M rows), tighter incremental (~1.5 years, ~16M rows).
3. **Cutoff at 2016-01-01** — maximum backfill (~5 years, ~54M rows), only ~6 months incremental.

**Chosen:** Option 1 — cutoff at 2014-01-01.

**Trade-off accepted:** Less "we already had years of history" weight than option 3, but more headroom for Airflow demo runs in Phase 3. Phil's original instinct, validated against the alternatives. 2.5 years of incremental headroom is overkill (we'll only simulate a few dozen days in demos) but harmless.

**Mechanics:** the extract script (`scripts/extract_azure_to_snowflake.py`, next session) is written once and used in two modes:

- **Backfill mode:** run once with a wide date range covering 2011-01-29 → 2013-12-31. Off-hours, slow, who cares.
- **Incremental mode:** run by Airflow each day, one date at a time, starting 2014-01-01.

Same script, two invocations. This is the standard production pattern — one tool, two modes.

**Why this matters:** Phase 3 needs a credible "the pipeline runs nightly and picks up new data" story. With 2.5 years of unprocessed dates sitting in Azure SQL, Airflow has something *real* to walk through. Each scheduled run actually processes new rows.

### 2026-05-13 — `loaded_at` audit column on every Snowflake RAW table

**Considered:** Mirror the Azure SQL raw tables exactly — same columns, nothing else.

**Chosen:** Add `loaded_at TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() NOT NULL` to all three RAW tables in Snowflake.

**Trade-off accepted:** Tiny divergence from Azure SQL shape (one extra column) in exchange for free lineage on every row. The `DEFAULT` means the extract script doesn't need to populate it — Snowflake stamps it on insert. No code complexity.

**Where it pays back:** Phase 3 "did the pipeline run today?" health checks (`SELECT MAX(loaded_at) FROM raw.sales_train`), debugging late-arriving rows, dbt source freshness tests. Standard practice in raw landing layers — cheap to add now, painful to retrofit.

---

## Pipeline orchestration

> Project #1 was manual. Project #2's headline is orchestration. This section
> captures the orchestration design and lessons learned implementing it.

_(to be populated during Phase 3)_

---

## What I'd do differently next time

> Lessons that should carry forward to Project #3.

_(to be populated through the project, finalised at the end)_

---

## Open questions / things still shaky

> Things I haven't fully understood yet. Useful for spotting where to dig deeper
> in Project #3, or for interview prep where I should expect questions.

_(to be populated as questions come up)_

---

## Carry-forward to Project #3

> What I want to do from day one of the financial markets / lakehouse project.

_(to be populated near end of Project #2)_
