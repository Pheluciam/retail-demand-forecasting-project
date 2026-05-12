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
- Trade-off: marginally more CPU on write, *faster* reads (less I/O), no query-side complexity. No reason not to use it on any raw table over a few million rows. Skipped on `calendar` (1,969 rows — overhead dwarfs savings).

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

*(to be populated during Phase 2 — warehouse / database / schema setup, COPY INTO,
query patterns, cost management)*

### Airflow

*(to be populated during Phase 3 — Docker compose stack, DAG patterns, scheduling,
failure handling, secrets management)*

### dbt (advanced from Project #1)

*(to be populated during Phase 4 — incremental models, partitioning, dbt_utils,
tests, marts layering)*

### Power BI (advanced from Project #1)

*(to be populated during Phase 5 — explicit DAX measures, cross-page slicers,
drill-throughs, format painter, themes)*

### Docker

*(to be populated as encountered — containerisation patterns, docker-compose,
networking between containers)*

### Git / GitHub Actions

*(to be populated as encountered — branching, PRs, CI workflows, sqlfluff lint)*

---

## Mistakes & diagnoses

> Each entry: Symptom → Diagnosis → Fix → What this taught me.
> Capture mid-project, not just at end. Project #1 had ~6 of these — this section
> is where future-me looks first when something goes wrong.

### 2026-05-12 / 2026-05-13 — Verified the shape, not the product

**Symptom:** Overnight bulk load script ran cleanly for 11 hours, then exited with `ValueError: Row count mismatch for raw.sales_train: got 59,181,090, expected 59,180,090` at the very end. Looked like a load failure when first seen in the morning terminal.

**Diagnosis:** Data was correct. The script's `EXPECTED_ROWS["sales_train"]` constant had an off-by-1000 arithmetic error: `30,490 series × 1,941 day columns = 59,181,090`, not the 59,180,090 written in the constant. The verification function correctly compared `actual != expected` and raised — exactly as designed. The *expected value itself* was wrong.

**Fix:** Updated `EXPECTED_ROWS["sales_train"]` to 59,181,090 in `scripts/load_m5_to_azure_sql.py`. Confirmed actual data via manual `SELECT COUNT_BIG(*)` in Azure Query editor (matched 59,181,090). No re-load needed.

**What this taught me:** Verifying the *shape* of an arithmetic operation ("30,490 rows × 1,941 day columns") is not the same as verifying the *product*. The dimensions were checked correctly (CSV inspection confirmed 30,490 rows and 1,941 day columns), but the multiplication itself was wrong by 1,000 and never independently recomputed — writing "30,490 × 1,941" makes the answer feel obvious enough not to double-check.

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

**Trade-off accepted:** Slightly more complex extract script (must accept a `run_date` parameter and filter `WHERE sale_date BETWEEN data_interval_start AND data_interval_end`) in exchange for a dramatically more credible orchestration story. Incremental dbt models, dbt tests, and failure alerts all have something *real* to fire on — each Airflow run actually processes new rows, instead of looping over the same static set every night.

**Why this matters for the portfolio:** the headline of Project #2 is orchestration. Option A reduces the schedule to theatre. Option B makes "runs daily, picks up new data, transforms, tests, alerts on failure" a true statement.

### 2026-05-12 — Wide-to-long unpivot moved from dbt staging to Python load

**Considered:** Keep the locked Phase 0 decision — load M5 sales wide-as-is into Azure SQL, do the unpivot in dbt staging downstream.

**Forced re-decision:** Azure SQL's 1024-column-per-table hard limit means M5's wide sales tables (1947 / 1919 columns) cannot physically be loaded wide. Three options considered:
1. **Unpivot in Python** during the load step using `pandas.melt`. Long table lands directly in `raw.sales_train`.
2. **Sparse columns** (allow up to 30,000 cols). Preserves the original plan but introduces an unusual feature, hurts query performance, and makes the dbt staging unpivot awkward over 1900+ columns.
3. **Split wide tables** into chunks of ~960 cols each. Ugly, fragmented downstream.

**Chosen:** Option 1 — unpivot in Python.

**Trade-off accepted:** Loses the "raw layer = 1:1 with source CSV shape" purity, in exchange for not fighting the database engine. dbt staging now does cleaning, casting, and renaming — not shape transformation. Load time roughly 2-3× longer (10-30 minutes for full sales table) but no other compromises.

**General rule learned:** column-count limits of the *specific* destination engine must be verified before locking source-shape decisions. The original plan would have worked on Snowflake or Postgres but not SQL Server. Project #3 carry-forward.

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

---

## Pipeline orchestration

> Project #1 was manual. Project #2's headline is orchestration. This section
> captures the orchestration design and lessons learned implementing it.

*(to be populated during Phase 3)*

---

## What I'd do differently next time

> Lessons that should carry forward to Project #3.

*(to be populated through the project, finalised at the end)*

---

## Open questions / things still shaky

> Things I haven't fully understood yet. Useful for spotting where to dig deeper
> in Project #3, or for interview prep where I should expect questions.

*(to be populated as questions come up)*

---

## Carry-forward to Project #3

> What I want to do from day one of the financial markets / lakehouse project.

*(to be populated near end of Project #2)*
