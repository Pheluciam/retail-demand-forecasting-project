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

**`write_pandas` bulk-load economics (2026-05-13, Phase 2 session 2)**

- Confirmed throughput on the production extract path (Azure SQL Free Serverless → pandas → `write_pandas` → Snowflake XS warehouse): **~14,000-15,000 rows/sec sustained** on 100k-row chunks for `sales_train` (8 narrow cols). `sell_prices` (4 narrow cols) hit ~10,500 rows/sec on a 27k single-chunk load. Orders of magnitude faster than Phase 1's `pandas.to_sql` + `fast_executemany` to Azure SQL (~1,500 rows/sec).
- The cost difference reflects architecture, not language: `write_pandas` PUTs a Parquet file to an internal stage then issues one `COPY INTO`, which Snowflake processes in parallel against its micro-partition writer. `fast_executemany` against SQL Server is still row-batched INSERTs at heart.
- **Implication:** the Phase 3 Airflow daily run will move ~30k sales rows in <10 seconds of compute. The warehouse barely wakes up before going back to sleep. Credit burn is negligible at this scale.

**Snowflake connector transient retry — built-in (2026-05-13)**

- Hit a transient `RemoteDisconnected('Remote end closed connection without response')` mid-PUT during the 7-day extract test. **The connector's internal retry handled it cleanly** — `Retrying (Retry(total=0, ...))` log line, then next chunk succeeded. Zero data lost, no special handling needed in our code.
- Worth knowing for interview talking points: Snowflake Python connector ships with `urllib3`-level retry on transient HTTP failures. You don't need to wrap `write_pandas` calls in your own retry loops. Different from `pyodbc` to Azure SQL where you need to think about it yourself.

**3-year backfill economics (2026-05-14, Phase 2 session 3)**

- **Total wall-clock for 35.6M rows across 3 tables: 27.3 minutes (1,638 sec).** Against an original fear of 40 hours and a session-2 revised estimate of 60-90 min. The "one wide query, paid the table-scan cost once" pattern delivered.
- **Per-table elapsed (from extract log timestamps):**
  - `calendar` — ~4 sec for 1,068 rows
  - `sell_prices` — ~85 sec for 3,040,105 rows
  - `sales_train` — ~25 min 47 sec for 32,563,320 rows (326 chunks of 100k, except the last which was a partial 63,320)
- **Sustained throughput on the production run** — both materially higher than session 2's spot-test measurements:
  - `sell_prices` (4 cols): ~35,500 rows/sec — vs session 2's 10,500. ~3.4× faster.
  - `sales_train` (8 cols): ~22,000 rows/sec — vs session 2's 14,500. ~1.5× faster.
- **Why the speedup vs session 2 measurements:**
  - **Bigger chunks amortise overhead better.** Session 2's sell_prices test was a single 27k-row chunk; backfill ran 100k-row chunks back-to-back. Per-chunk fixed costs (Parquet encode, PUT, COPY INTO) get paid less often per million rows.
  - **Warmer infrastructure.** Snowflake's internal-stage upload path felt sharper at AU morning vs session 2's late afternoon. Cloud services have time-of-day variation worth noting.
- **End-to-end parity verified two ways:**
  - Script's own pre-flight (Azure SQL source count) vs post-action (Snowflake destination written count) — all three tables `OK`.
  - Independent SQL queries against both databases (`sql/snowflake/02_extract_smoke_tests.sql` Section 5 + `sql/verify/02_phase2_extract_verification.sql`) — all three tables `OK / OK / OK`.
- **Zero retries fired during the run.** No 40613 errors mid-stream, no transient HTTP disconnects mid-PUT. (Did hit one 40613 on the very first connect attempt — see Mistakes & diagnoses.)

### 2026-05-18 — Snowflake metadata visibility ≠ access boundary

Discovered during Phase 5 session 1 while connecting Power BI Desktop. PBI's Navigator under the dedicated `POWERBI_READER` role showed *all 7 schemas* in `RETAIL_DB` (`INFORMATION_SCHEMA`, `INTERMEDIATE`, `MARTS`, `PUBLIC`, `RAW`, `STAGING`, `WAREHOUSE`) — even though the role only had USAGE on `WAREHOUSE` and `MARTS`. Surprising; looked like a privilege leak. Diagnosed via `INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER('PHELUCIAM')`, which proved every PBI metadata query (`SHOW SCHEMAS IN "RETAIL_DB"`, `SHOW DATABASES`, etc.) ran under `POWERBI_READER` — the role pin worked at the session level.

**The real behavior**: Snowflake's `SHOW SCHEMAS IN DATABASE` returns *every schema name* in a database the role has DB-level USAGE on, **regardless of per-schema privileges**. Schema-level USAGE controls whether you can OPEN the schema and READ tables inside it — not whether the schema name appears in catalog listings. The metadata layer is broadly readable; the access layer is privilege-gated.

**Visitor-badge analogy.** Walk into a building with a visitor pass. The elevator directory lists *every floor*: Marketing, Engineering, Executive, etc. That listing isn't a security hole; it's just signage. The badge readers on each individual floor's door are what enforce who can actually enter. Snowflake's `SHOW SCHEMAS` is the directory; the USAGE/SELECT grants are the badge readers.

**How we proved the boundary holds anyway**: `SELECT COUNT(*) FROM RETAIL_DB.RAW.M5_SALES_TRAIN` under `POWERBI_READER` failed with "Object does not exist or not authorized" — exactly as designed. PBI's Navigator showing the RAW schema name in the tree is cosmetic; if you'd tried to expand it and tick a table to load, the load itself would have errored with the same auth message.

**Carry-forward**: when a Snowflake catalog listing looks broader than expected, the question to ask is not "what did the GRANTs miss?" but "does an actual SELECT against the surprising object succeed?" Metadata is broadly readable; access is the boundary. Same pattern likely holds in BigQuery, Databricks Unity Catalog, and other modern warehouses. Project #3 carry-forward.

**Diagnostic technique worth banking**: `INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER('<user>')` filtered to the last N minutes is the canonical way to verify what role any connecting tool is actually using — beats guessing-from-symptoms decisively. Add this to the Project #3 troubleshooting toolkit early.

### 2026-05-19 — ML training workload sizing: sample, validate, then scale

Discovered during Phase 5 session 5.3 while training the Snowflake Cortex ML FORECAST model. Claude scoped training at the full fact grain — 30,490 (item × store) series × ~1,150 days = ~35M training rows — and pointed it at the XS warehouse (1 credit/hr, single-node). Training ran for 90+ minutes (and possibly longer; Phil chose to let it finish rather than cancel mid-run after waiting ~80 min).

**The mistake**: scoping the ML workload to "production grain" before validating it ran in a tolerable time at all. Cortex multi-series scales reasonably well, but 30K series on XS is squarely on the high end of what XS handles efficiently. The single Cortex training run consumed roughly half a credit (acceptable cost) but a disproportionate share of Phil's wall-clock patience (not acceptable).

**Forward principle — ML workload scoping checklist**:

1. **Sample first.** Train on a small representative subset (e.g., 100-500 series, recent N months only) and measure wall-clock. Multiply out conservatively to the full grain — if the projection exceeds 30 min, decide before starting whether that's tolerable or scope needs reducing.
2. **Match warehouse / cluster size to workload.** For Cortex multi-series at 10K+ series, MEDIUM warehouse trains materially faster than XS for marginal extra cost (warehouse cost scales linearly but training time scales sub-linearly). Same principle applies on Databricks (autoscaling cluster vs single-node).
3. **Pick the right grain for the use case, not "the same grain as the fact."** If the Forecast vs Actual page surfaces category-level trends, item × day or category × day is sufficient and trains in minutes. Item × store × day is operationally useful but only if inventory/replenishment is the actual use case.
4. **Communicate runtime expectations BEFORE starting.** Anything > 5 min should come with a flagged time estimate so the user can decide to schedule it, walk away, or scope down.

**Carry-forward to Project #3**: Databricks ML workloads (MLflow / Spark MLlib / AutoML) have the same shape. Sample first, size cluster to projected runtime, communicate expectation, scale up only when correctness is proven at small scale. Community Edition Databricks is single-node and slow — paid trial or per-workload cluster sizing matters more there than on Snowflake's auto-suspend warehouse model.

**Discipline rule logged in TEACHING_PREFERENCES separately**: any operation Claude proposes that's expected to exceed 5 minutes must be flagged with explicit time estimate up front; any operation that ends up >2x the estimate is a triggered post-mortem.

**Resolution.** After cancelling the item × store training at 2h20min (still running, status confirmed RUNNING via Query History), pivoted to item-level grain (3K series). New training completed in the expected 3-5 min window. Lesson durably captured: the **right grain for a forecast is the grain that matches the use case AND trains in a tolerable window**, not "the same grain as the fact table." Item × store would only have earned its keep if the dashboard surfaced per-store forecasts as a primary visual. The Forecast vs Actual page surfaces aggregate revenue/units trends — item-level is the right grain. Interview talk track: *"I chose item-level forecasting over item × store because aggregated series have stronger signal — each item's daily demand across all stores is more stationary than per-store splits. Standard retail forecasting pattern when stores share similar SKU mixes."*

### 2026-05-20 — Cortex ML training is MEMORY-bounded, not just runtime-bounded, when using `method='best' + evaluate=TRUE`

Direct follow-up to the entry above. After fixing the GRAIN problem (item-level not item × store), the next training run at the right grain was kicked off overnight on XS warehouse with `method='best' + evaluate=TRUE` for portfolio-grade quality. Expected runtime per Snowflake docs was 60-120 min. Actual outcome: at 1h40m, the run failed with `STATEMENT_ERROR: Function available memory exhausted` (Snowflake's `_BASECONSTRUCT` UDF OOM'd inside the Python sandbox running the Cortex training).

**The mistake — second one in two days on the same workload.** Even at the right grain (3K series, ~3.5M training rows), `method='best' + evaluate=TRUE` is materially heavier on RAM than `method='fast'` because:

- `best` ensembles 4-5 models (Prophet, ARIMA, ExpSmoothing, GBM) in parallel — each model's per-series state is held in memory simultaneously across the cross-validation folds.
- `evaluate=TRUE` runs cross-validation splits which multiplies the in-memory model state by the number of folds.
- The XS warehouse on Snowflake is single-node with ~16 GB RAM available to UDFs. The combined ensemble + CV state on 3K series exceeded that ceiling at ~1h40m into the training.

**The recovery path that worked.** Bumped warehouse to XL (`ALTER WAREHOUSE WH_RETAIL SET WAREHOUSE_SIZE = 'XLARGE'`), re-ran the same SQL, completed in ~15 min. Cost ~1-2 credits total (XL is 16 credits/hr but only ran ~15 min). Then immediately bumped warehouse back to XS via `SET WAREHOUSE_SIZE = 'XSMALL'` as the last statement in the script so it didn't sit idle at XL between training runs.

**The forward principle.** Warehouse sizing decisions for ML workloads must weight RAM headroom separately from CPU time. The standard guidance "smaller warehouse runs longer for less cost" works for SQL transformations (CPU-bounded) but breaks for ML training (memory-bounded). Specifically for Cortex:

- `method='fast'` on XS: ~3 min on 3K series, fits in RAM, ~0.05 credits.
- `method='best' + evaluate=FALSE` on XS: probably 30-60 min, may fit in RAM. Untested in this session.
- `method='best' + evaluate=TRUE` on XS: OOM at 1h40m on 3K series. Memory ceiling exceeded.
- `method='best' + evaluate=TRUE` on XL: ~15 min on 3K series. Memory headroom + horizontal compute. ~1-2 credits.

**Interview talk track**: *"For portfolio-quality forecasting I went with method='best' + evaluate=TRUE which ensembles 4 models and runs cross-validation. The XS warehouse hit a memory ceiling at 1h40m — the ensemble holds per-series state for all 4 models plus CV folds simultaneously, which exceeded the single-node RAM. Bumped to XL warehouse, ran in 15 min for ~1-2 credits, then immediately dropped back to XS. The lesson: ML workload sizing is memory-bounded not just time-bounded, so picking the warehouse on cost-per-minute alone is the wrong heuristic."*

**Carry-forward**: applies identically to Databricks ML clusters in Project #3 — single-node clusters with tight RAM ceilings work for small-feature workloads but blow up on ensemble + CV training. Size cluster for memory headroom on training workloads, then scale down for inference/query workloads.

### Airflow

**Stack architecture choices (2026-05-14, Phase 3 session 1)**

- **Self-contained `airflow/` subdirectory.** Everything Airflow-related — `docker-compose.yml`, the custom `Dockerfile`, `requirements-airflow.txt`, `dags/`, `plugins/`, `logs/` — lives under one folder. Project root stays clean. The compose file mounts the parent project's `scripts/` folder read-only into the containers so the DAG can call the existing `extract_azure_to_snowflake.py` without code duplication.
- **LocalExecutor, not CeleryExecutor.** Airflow has several "executor" engines deciding how tasks actually run. LocalExecutor runs each task as a subprocess on the scheduler container — adequate for a single-DAG portfolio project. CeleryExecutor adds a Redis broker plus N worker containers — required at production scale, overkill here. Worth knowing the upgrade path exists: same DAG code, just swap executor + add services in compose.
- **Four containers in the stack.** `postgres` (Airflow's own metadata DB, not our retail data), `airflow-init` (one-shot bootstrap that runs `airflow db migrate` and creates the admin user, then exits), `airflow-webserver` (UI at `localhost:8080`), `airflow-scheduler` (parses DAGs, schedules + runs tasks). Init `depends_on: postgres: condition: service_healthy`; webserver and scheduler `depends_on: airflow-init: condition: service_completed_successfully` — ordered startup is declarative.
- **One `.env`, two execution environments.** `env_file: - ../.env` in the compose anchor passes our existing Azure SQL + Snowflake creds into every Airflow container as env vars. The extract script's `os.getenv("AZURE_SQL_SERVER")` calls work identically inside Airflow and from PowerShell — zero environment-specific branching in our code. One source of truth for secrets.

**Custom Airflow image — never reuse the project-root `requirements.txt` (2026-05-14, Phase 3 session 1)**

Two-stage failure during the first build of the custom Airflow image:

- **Stage 1 — no `--constraint` flag, install our `requirements.txt` directly.** Build succeeded; `airflow-init` immediately crashed with `sqlalchemy.orm.exc.MappedAnnotationError: Type annotation for "TaskInstance.dag_model" can't be correctly interpreted...`. Airflow 2.10 needs SQLAlchemy **1.4.x**; our `requirements.txt` has `>=2.0.0`. pip upgraded past what Airflow could handle.
- **Stage 2 — same `requirements.txt`, now with `--constraint` pointing at Airflow's official constraints file.** Build failed at pip with a dependency-resolution error. Constraint says SQLAlchemy 1.4.x, requirement says ≥ 2.0.0 — pip refuses a direct conflict. `--constraint` alone isn't enough; the underlying disagreement still has to be fixed.

**The fix that worked: separate `airflow/requirements-airflow.txt` with no version pins.** Lists only the extras the extract script needs (`pyodbc`, `python-dotenv`, `snowflake-connector-python[pandas]`). `--constraint` pointed at `https://raw.githubusercontent.com/apache/airflow/constraints-2.10.3/constraints-3.11.txt` chooses tested versions for everything. Build clean, runtime clean.

**General principle for any custom image extending an opinionated base.** Don't blanket-apply existing pin lists onto an image whose maintainers have already thought hard about compatible versions. List only the *additional* packages, leave them unpinned, let the base image's constraints decide. Same lesson applies to a custom `dbt-core` image, a custom Jupyter image, anything layering deps onto a curated stack.

**Carry-forward:** add "look at constraints/lockfile of base image before adding deps" to the Code-Quality checklist as a corollary of criterion 1 (Currency). Project #3 carry-forward — most production Docker images extend an opinionated base.

**Docker daemon must be running before `docker compose` (2026-05-14, Phase 3 session 1)**

Trivial-in-hindsight but worth noting because the error message is opaque: `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`. That long path is Docker Desktop's named pipe on Windows. The error is just "Docker Desktop isn't running." Fix: open Docker Desktop from the Start menu, wait for the whale icon in the taskbar to stop animating (settles to solid), then retry. The CLI (`docker`, `docker compose`) is a thin client that talks to a background service — the service has to be alive for any command to work.

**Code-quality framework gap discovered: dev environment hygiene (2026-05-14, Phase 3 session 1)**

Mid-session, yellow Pylance squigglies appeared on the freshly-written DAG file (`airflow/dags/m5_daily_extract.py`) — `import pendulum`, `from airflow.decorators import dag, task`, `import extract_azure_to_snowflake`. Phil pushed back: shouldn't `CODE_QUALITY.md` have flagged this *before* it became a problem?

**Diagnosis.** The lunch audit had been thorough — but all nine criteria audit what's *inside* the code (idioms, security, types, idempotency, observability). None audited the *dev environment around* the code. A genuine gap in the framework.

**Fix.** Three coordinated edits:

- Added criterion 6 to `CODE_QUALITY.md`: "Dev environment hygiene." Linter warnings zero-tolerance, IDE imports resolve to the runtime modules, local venv mirrors deployed environment.
- Renumbered the rest (6→7, 7→8, 8→9, 9→10); "six core checks" → "seven core checks."
- Mirrored in `TEACHING_PREFERENCES.md`.

**Practical-fix corollary.** Yellow squigglies addressed with the canonical Windows-host workaround:

- `pip install pendulum "apache-airflow==2.10.3" --no-deps` — installs Airflow source files for Pylance import-resolution without dragging in 100+ Unix-only transitive deps.
- `pyrightconfig.json` at project root with `extraPaths: ["scripts"]` — maps the DAG's runtime `sys.path.insert(0, "/opt/airflow/scripts")` to the host's `scripts/` folder.
- *Truly* professional answer is **VS Code Dev Containers** (editor attaches to the running container; zero drift). Flagged as Phase 6 polish — strong interview talking point about progression from pragmatic-now to modern-later.

**What this taught me.**

- A code-quality checklist is a living artefact — when a mistake bypasses it, the checklist is the artefact to improve. Updating alongside the fix pays compounding interest across all future projects.
- "Code quality" and "dev environment quality" are distinct concerns; both deserve explicit criteria. Conflating them means dev-env issues hide as random IDE complaints rather than being treated as the same silent-bug class.
- Carry-forward to Project #3: criterion 6 starts day one — pyrightconfig, IDE-resolves-runtime imports, linter-warnings-zero-tolerance baked into Phase 0 scaffolding.

**Airflow 2.x CLI flag is `-e` / `--exec-date`, not `--logical-date` (2026-05-14, Phase 3 session 1)**

First attempted to manually trigger the DAG for a specific past date with `airflow dags trigger m5_daily_extract --logical-date 2014-01-02T00:00:00`. Failed with `airflow command error: unrecognized arguments: --logical-date 2014-01-02T00:00:00`.

**Diagnosis.** `--logical-date` only landed in Airflow 3.x. Airflow 2.10 still uses `-e` (short form) or `--exec-date` (long form). The terminology shift `execution_date` → `logical_date` happened in stages:

- Airflow 2.2 (2021): renamed the Python API parameter (the macro available to DAG code).
- Airflow 3.0: finally followed through and renamed the CLI flag to match.
- Airflow 2.x in between: Python code references `logical_date`, CLI still uses `--exec-date` for backward compatibility. This terminology mismatch is invisible in tutorials that show only Python, but bites the moment you go to the CLI.

**Fix.** Use `-e`:

```powershell
docker compose exec airflow-scheduler airflow dags trigger m5_daily_extract -e 2014-01-02T00:00:00
```

**Carry-forward.** Run `airflow version` (or `docker compose exec airflow-scheduler airflow version`) before constructing CLI invocations against a new Airflow stack. Tutorial syntax written for Airflow 3.x will silently fail on 2.x for at least this one flag. Same family of risk as "ODBC Driver 17 vs 18" — version-specific names that look interchangeable but aren't.

**`catchup=False` semantics: still runs the most recent interval on unpause (2026-05-14, Phase 3 session 1)**

When the DAG was unpaused via the UI toggle, an unexpected scheduled run fired immediately for `scheduled__2026-05-12T14:00:00+00:00` — even though the DAG has `catchup=False`. Caught me out: I assumed `catchup=False` meant "no scheduled runs fire until the next scheduled interval boundary."

**Actual semantics.** `catchup=False` means: when the DAG is unpaused, Airflow runs *exactly one* scheduled instance — the most recent interval that has already ended — and skips all earlier missed intervals. The protection against "auto-backfill 4,500 days from 2014 forward" works as expected; what doesn't get protected is that *one* most-recent-interval run firing on unpause.

**Why it works this way.** Airflow's UX assumes that when you unpause a DAG, you want at least one run to fire so you can validate it works. Silent-until-next-tick would make it harder to know "did unpausing actually do anything?"

**For our setup this was a no-op:** the auto-fired run targeted "today's date" (~2026-05-14) which is outside the M5 dataset's calendar range. The script found 0 calendar rows for the window, logged the warning, and exited 0. Clean.

**Carry-forward to Project #3 and beyond.** If a DAG should *truly* not fire on unpause (e.g., it writes to a production table and you don't want an accidental run), don't rely on `catchup=False` to protect you. Either keep the DAG paused until you trigger explicitly, or guard the first task with a sensor that no-ops when the data interval is outside the safe window. Distinguishing "I want catchup off because I'd otherwise drown in backlog" from "I want zero auto-runs on unpause" matters.

**CTE-based PASS/FAIL verification template (2026-05-14, Phase 3 session 1)**

Captured for reuse across future projects. Lives concretely in `sql/verify/03_phase3_dag_extract_verification.sql` Section 5. The shape:

```sql
WITH expected AS (
    SELECT 'check_1' AS check_name, <expected_count_1> AS expected_rows UNION ALL
    SELECT 'check_2' AS check_name, <expected_count_2> AS expected_rows UNION ALL
    -- one row per check
),
actual AS (
    SELECT 'check_1' AS check_name,
        (SELECT COUNT(*) FROM <table_1> WHERE <filter>) AS actual_rows
    UNION ALL
    SELECT 'check_2',
        (SELECT COUNT(*) FROM <table_2> WHERE <filter>)
    -- matching one per check
)
SELECT
    e.check_name,
    e.expected_rows,
    a.actual_rows,
    CASE WHEN e.expected_rows = a.actual_rows THEN 'PASS' ELSE 'FAIL' END AS status
FROM expected e
JOIN actual a ON e.check_name = a.check_name
ORDER BY e.check_name;
```

**Why this pattern earns its keep:**

- **Single result set.** N checks roll up into one tidy table with a status column. At-a-glance "all PASS or any FAIL" with no scrolling through separate query results.
- **Hardcoded expected values force pre-commitment** to what "correct" means *before* running. Catches assumption drift — if you only ever look at the actual count, you have no anchor to disagree with.
- **Trivial to extend.** Add a check = add one row to `expected` and one to `actual`. Six lines of SQL for a new test.
- **Snowflake-agnostic.** Pure ANSI SQL; works the same on Postgres, BigQuery, Databricks SQL Warehouse. No dialect-specific bits.

**Carry-forward.** Any verification SQL file with two or more checks in future projects ends with a Section N rollup using this template. Cheap insurance; cost is ~30 lines of well-structured SQL per file. Detailed sections (1, 2, 3, ...) stay for debugging when a FAIL appears; the rollup is the headline.

**`verify_one_day` caught a real silent failure on first deploy (2026-05-15, Phase 3 session 2)**

Built `verify_one_day` as a second task in `m5_daily_extract`, downstream of `extract_one_day`. Three Snowflake-side checks (`CALENDAR` = 1 row for run_date, `SELL_PRICES` > 0 for the fiscal week, `SALES_TRAIN` > 0 for the d-code) batched into a single SQL round-trip with three positional `%s` binds. Queries Snowflake fresh — doesn't read the extract task's XCom. Closes the loop inside Airflow rather than relying on a manual Snowsight pass.

**The verify task caught a real silent failure within ten minutes of deployment.** Testing the manual `2014-01-03` trigger, the run stuck in `queued` forever — **paused DAGs don't execute manually-triggered tasks in Airflow 2.x**. Unpausing then auto-fired today's `2026-05-15` slot (because `catchup=False` only suppresses *historical backfill*, not the next scheduled interval). M5 doesn't cover that date — Azure SQL returned 0 rows, `extract_one_day` finished cleanly with no error, and `verify_one_day` queried Snowflake, found 0 calendar rows, raised `RuntimeError`. **Exactly the silent-failure shape the verify task was designed to catch.**

**Lessons.**

- **Independent verification beats trusting return codes.** If verify had read the extract task's XCom (`rows_written = 0`), the chain would have been "extract reported zero, verify confirms zero, all good." Querying Snowflake fresh closed that loop properly. A verify that depends on the extract's word is a verify with the same blind spots as the extract.
- **Silent failures are the dangerous failures.** A loud crash gets fixed within hours. A quiet zero-row extract that reports success can poison downstream dashboards, alerts, and dbt models for months before anyone notices the numbers stopped moving.
- **`catchup=False` is not the same as "no auto-runs."** It only suppresses backfill of skipped historical intervals. The first scheduled interval *after* unpause still fires. To suppress that too, separate config (e.g., `is_paused_upon_creation=True` on initial deploy, or just leaving the DAG paused) is needed.
- **Paused DAGs swallow manual triggers in Airflow 2.x.** The DAG run is created and queued, but tasks won't be scheduled. Operator confusion in the moment: "I triggered it but nothing's running." Resolution: unpause, let the run complete, re-pause after if metadata-DB clutter is the concern.

**Carry-forward.** Every DAG with a real-world data destination in future projects gets an independent verify task as part of its definition-of-done. The pattern is cheap — ~50 lines of Python plus a single SQL round-trip — and the value compounds because the alternative (trusting upstream return codes) fails silently exactly when it matters most.

Reference screenshots: `docs/screenshots/00_verify_caught_silent_failure_2026-05-15_log.png` (the Logs tab showing the three CALENDAR / SELL_PRICES / SALES_TRAIN count lines plus the `RuntimeError` message). Grid-view side-by-side screenshot deferred — can be regenerated from `m5_daily_extract` history at any time.

**`SHOW_TRIGGER_FORM_IF_NO_PARAMS=true` + the two-button UI gotcha (2026-05-15, Phase 3 session 2)**

Enabled the trigger-with-config form by adding `AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS: 'true'` to the shared `x-airflow-common.environment` block in `airflow/docker-compose.yml`, then full `down` + `up -d` (an env-var change is only picked up at container start). Verified the var landed two ways: `docker compose exec airflow-webserver env | findstr -i trigger` returned the variable, and `docker compose exec airflow-webserver airflow config get-value webserver show_trigger_form_if_no_params` returned `true` — confirming Airflow's own config system sees the setting, not just the OS env layer.

**UI gotcha that ate ~20 minutes.** Even with the flag correctly enabled, clicking the play-arrow "Trigger DAG" button on the DAG detail page still fired the run immediately with no form. Eventually figured out: Airflow 2.10's DAG detail page exposes **two distinct trigger buttons**. The play-arrow "Trigger DAG" always quick-fires (uses the current timestamp as logical_date). The dropdown-revealed **"Trigger DAG w/ config"** is the one that opens the modal with the calendar-icon Logical Date field + Configuration JSON area. The flag controls whether the form *exists* for no-param DAGs at all (it's hidden by default since 2.7) — it does not change which button calls it. Validated end-to-end by triggering for `2014-01-04T00:00:00+00:00` via the form; extract + verify both ran green.

**Lessons.**

- **Flags that change UI behaviour need TWO validations:** the env-var diagnostic (`env | grep`), *and* the actual user-facing click path. Either alone can mislead.
- **`airflow config get-value` is a better diagnostic than reading the env var.** It confirms Airflow's *config system* has resolved the setting, not just that the OS-level env var is present. Catches edge cases where the var landed but Airflow's section/key mapping is wrong.
- **In Airflow 2.10's UI, "Trigger DAG" and "Trigger DAG w/ config" are not the same control.** The first is always immediate; the second is always form-based. Browser cache and incognito mode are red herrings here.

Reference screenshot: `docs/screenshots/01_ui_trigger_form_with_date_picker.png` — the filled-in form showing Logical Date `2014-01-04T00:00:00+00:00`, Run id empty, Configuration JSON `{}`, ready to click Trigger.

**Harmless deprecation warning: `core/sql_alchemy_conn` (2026-05-15)**

Every Airflow CLI invocation inside the container prints:

```
FutureWarning: section/key [core/sql_alchemy_conn] has been deprecated, you should use [database/sql_alchemy_conn] instead. Please update your `conf.get*` call to use the new name
```

Our `docker-compose.yml` **already uses the new name** (`AIRFLOW__DATABASE__SQL_ALCHEMY_CONN`, line 44). The warning is emitted by Airflow's own internal compatibility shim that still reads the legacy `core/sql_alchemy_conn` section path somewhere inside `airflow.configuration`. Functional impact: zero. Audit trail: confirmed by grepping `docker-compose.yml` and `Dockerfile`, neither contains the old name.

**Carry-forward.** Leave it alone. The warning will disappear when we upgrade to Airflow 3.x or whenever upstream cleans up the internal reference. Logged here so that future-me sees the warning, recognises it, and moves on without spending time chasing a non-issue.

### 2026-05-17 — Astronomer Cosmos: per-model task generation for dbt (Phase 4 session 6)

The headline session-6 work. Replaced what would have been a `BashOperator` shelling out to `dbt build` with a `DbtTaskGroup` from `astronomer-cosmos`. At DAG-parse time, Cosmos reads the dbt project's manifest, walks `ref()` dependencies, and **generates one Airflow task per dbt model + one per dbt test**, with the Airflow Graph view showing the dbt DAG directly. 13 lines of Cosmos config replaced what would have been ~150 lines of hand-wired BashOperator tasks and dependency wiring.

**Three pieces of installation surface:**

1. `astronomer-cosmos>=1.7,<2.0` in `airflow/requirements-airflow.txt` — Cosmos itself, range-pinned because Cosmos ships breaking changes between major versions.
2. Separate Python venv inside the Dockerfile at `/opt/airflow/dbt_venv` with `dbt-core==1.11.10 dbt-snowflake==1.11.5` — isolated from Airflow's pinned deps to avoid `jinja2` / `pyyaml` conflicts. Astronomer's documented recommended pattern.
3. `../dbt:/opt/airflow/dbt:ro` mount in `docker-compose.yml` — read-only window for Cosmos to read the dbt project files at DAG-parse time. Same pattern as the existing `../scripts:/opt/airflow/scripts:ro` mount from Phase 3.

**Cosmos default `test_behavior=AFTER_EACH`**: each dbt model becomes a sub-TaskGroup containing a `run` task (DbtRunLocalOperator) and a `test` task (DbtTestLocalOperator) that fires immediately after the model. Failing tests halt dependent models cleanly. Alternatives (`AFTER_ALL`, `BUILD`) are configurable via `RenderConfig` but `AFTER_EACH` is the right default for fail-fast pipelines.

**Carry-forward**: per-model task generation as the default for any future dbt + orchestrator combo (Dagster's dbt assets, Prefect's `prefect-dbt`, Argo, etc.). Single source of truth (the dbt project) beats duplicate maintenance across two task lists.

### 2026-05-17 — Cosmos lazy imports + the submodule workaround for Pylance

The natural import `from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig` worked at runtime in the Airflow worker but triggered Pylance errors locally: *"Object of type object is not callable. Attribute __call__ is unknown."* Cause: Cosmos's `cosmos/__init__.py` uses **lazy imports via `__getattr__`** for memory and startup-time reasons — the class names aren't statically present in the namespace; they're loaded dynamically on first access. Pylance can't follow `__getattr__` magic and degrades the unresolved names to bare `object`, producing the "not callable" diagnostic.

**Fix**: import each class from its actual submodule path:

```python
from cosmos.airflow.task_group import DbtTaskGroup
from cosmos.config import ExecutionConfig, ProfileConfig, ProjectConfig
```

Runtime behaviour is identical (Python loads the same classes either way), but Pylance can statically resolve the submodule paths. Clean diagnostics, zero `# type: ignore` suppression. Confirmed by reading `cosmos/__init__.py` directly: a `_LAZY_IMPORTS: dict[str, str]` declares the mapping from public names to their submodule paths.

**Carry-forward**: when Pylance reports "Object of type object is not callable" on a third-party class import, suspect lazy imports / `__getattr__` magic. Read the package's `__init__.py` to find the actual submodule path and import from there.

### 2026-05-17 — Airflow data_interval semantics: logical_date vs ds

Got tripped during the end-to-end manual trigger. Set Logical Date to `2014-03-22 00:00:00` in the trigger form; the run actually processed data for **2014-03-21**, not 2014-03-22. Quick reference:

| Field | What it means |
|---|---|
| `logical_date` | The END of the data interval (formerly "execution_date") |
| `data_interval_start` | Start of the data period the run processes |
| `data_interval_end` | End of the data period (= `logical_date`) |
| `{{ ds }}` template | `data_interval_start.strftime('%Y-%m-%d')` |

For `@daily` schedule, triggering `logical_date = X` processes data for the previous day (`X − 1`). Easy to miss for manual triggers because the form labels the field "Logical Date" without explaining the off-by-one relative to the data actually being processed.

**Carry-forward**: when triggering a DAG manually for "data date X," set the Logical Date to `X + 1`. Or design the DAG with task code that explicitly uses `data_interval_start` rather than relying on a `ds` template that could be misread.

### 2026-05-17 — Airflow task states: `upstream_failed` vs `failed`

Demonstrated cleanly during the failure-injection test. When `dbt_models` went red (a model's test failed), the downstream `verify_dbt_one_day` task did **not** turn red — it turned **orange / upstream_failed**. Key distinction:

- `failed` = the task executed and failed (raised an exception, exited non-zero, etc.)
- `upstream_failed` = the task **never executed**; an upstream task in the dependency chain failed, and the task's `trigger_rule="all_success"` (the default) means "only run if all upstream succeeded"

The tooltip on the upstream_failed task confirmed: `Duration: 00:00:00`, `Trigger Rule: all_success`. The task was skipped without firing, which is exactly what fail-fast pipelines want — no broken-data verifications running on top of a broken dbt build.

**Other `trigger_rule` values worth knowing**:

| Rule | Behaviour |
|---|---|
| `all_success` (default) | Run only if all direct upstream tasks succeeded |
| `all_failed` | Run only if all direct upstream tasks failed |
| `all_done` | Run regardless of upstream state (success, failed, or skipped) |
| `one_success` | Run if any upstream succeeded |
| `none_failed` | Run if no upstream failed (success or skipped) |

`all_done` is useful for cleanup tasks (always run, even after pipeline failure). `one_success` is useful for "any one of these branches has the data we need" patterns. For verify-gate tasks like `verify_dbt_one_day`, the default `all_success` is exactly right.

### 2026-05-18 — DAG state ownership: the scheduler tracks "where we're up to," not me

Came up during Phase 5 session 1 while thinking about the interview demo. The manual-trigger UX during testing — typing a date into the form every time — created the wrong mental model: that I was responsible for remembering which date the DAG was up to. I'm not. Airflow is.

**The actual state model.** Airflow's metadata DB records every DAG run — `logical_date`, start time, end time, final state — and the scheduler reads that table to decide what to run next. With `schedule="@daily"` + `catchup=False`, an unpaused DAG fires exactly one new run per scheduled interval going forward, regardless of how many intervals were missed while paused. The scheduler maintains the cursor; I just look at it.

**Three places the cursor is visible** (any one is enough to answer "what's the next date to run?"):

| Surface | How to read it |
|---|---|
| **Airflow UI → Grid view** | Each column = a `logical_date`. Rightmost green square = latest success. Next date to run = column one to the right. Screenshot-ready for interview/portfolio. |
| **`SELECT MAX(sale_date) FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES`** | Snowflake's view of the truth. After session 6's two runs this returns `2014-03-23`. Next date to process = MAX + 1 = `2014-03-24`. Survives even if Airflow's metadata DB is wiped. |
| **`airflow dags list-runs -d m5_daily_extract`** (CLI) | The same data the Grid view renders, tabular. Useful in scripted environments / over SSH. |

**Why I'd been "putting in dates" anyway.** Manual UI triggers (the trigger-with-config form) are for *testing specific dates without waiting* — backfills, replays, demos. That's a dev-time affordance, not the prod control surface. In production the DAG runs untouched on its schedule; nobody types a date in.

**`catchup=False` is a deliberate design call worth defending in interviews.** With `catchup=True` (Airflow's default), unpausing this DAG today would queue ~2.5 years of runs back-to-back and burn Snowflake credits in one burst. With `catchup=False`, only one run fires per real day going forward — the "simulated freshness" pattern, where the DAG advances one M5 date per real-world midnight. Bounded-backfill datasets like M5 should default to `False`; rolling-window datasets (sensor data, transactional logs) often want `True`.

**Two power moves to keep banked**:

- **Backfill on demand.** `airflow dags backfill m5_daily_extract -s 2014-03-24 -e 2014-03-26` (CLI) fires three dates back-to-back from a known start to end. Useful for "the upstream data was corrected — replay the last week" scenarios. Makes a strong mid-demo move because it shows the scheduler picking up exactly where it left off.
- **Pause / unpause.** Toggling the DAG off in the UI freezes the cursor in place. Unpausing resumes from the next-unfilled interval, not from a "rewind 5 days" position. The cursor never drifts.

**Interview talk-track sentence**:

> *"Airflow's scheduler owns the state, not me. The metadata DB tracks every run; the Grid view renders it. I set `catchup=False` deliberately because for this simulated-freshness pattern I want one date per real day, not a 2.5-year burst at unpause. Backfills and replays go through the CLI when I need them — pause/unpause never loses the cursor."*

**Carry-forward to Project #3**: every scheduler-driven DAG has three "where are we up to" surfaces — the scheduler's own state, the data destination's MAX-of-watermark column, and a CLI introspection command. Wire all three explicitly so a question about pipeline state has a 30-second answer regardless of who's asking. Avoid mental models that put state in your head.

### dbt (advanced from Project #1)

**Installing dbt-snowflake alongside the Phase 3 `--no-deps` Airflow stub (2026-05-15, Phase 4 session 1)**

First `pip install dbt-snowflake` printed a wall of "apache-airflow 2.10.3 requires X, which is not installed" warnings plus one "sqlalchemy 2.0.49 is incompatible" line. **All harmless** — direct consequence of Phase 3 session 1's deliberate `pip install pendulum "apache-airflow==2.10.3" --no-deps` (logged in Phase 3 LEARNINGS). The local-venv Airflow package was always a half-install for Pylance import-resolution purposes; the actual Airflow runtime lives inside Docker. dbt needs SQLAlchemy 2.x, the Airflow stub wants 1.4.x — they coexist because only dbt is ever actually *run* from this venv. The line that mattered: `Successfully installed dbt-core-1.11.10 dbt-snowflake-1.11.5`.

**Carry-forward.** Textbook "multiple tools in one venv" drift. The professional long-term fix is per-tool venvs or VS Code Dev Containers — already flagged as Phase 6 polish.

**Three-layer documentation pattern for code-shaped files (2026-05-15, Phase 4 session 1)**

Locked in mid-session after Phil pushed back on heavily-commented YAML being unsuitable for a portfolio repo. Now `TEACHING_PREFERENCES.md` policy for every code-shaped file going forward:

- **(a) Verbose, comment-rich version shown in chat** — comments-above-the-line style, every line explained. Phil's learning artefact for the session.
- **(b) Clean, professional version written to disk** — short header pointing at the walkthrough doc, only non-obvious-choice inline comments. What ships to git.
- **(c) Companion walkthrough markdown** at project root — `<COMPONENT>_PIPELINE.md` pattern, matches `EXTRACT_PIPELINE.md` from Phase 2. Lives in the repo, carries the depth.

**Why this matters.** A portfolio visitor skimming a heavily-commented `dbt_project.yml` reads "junior dev copy-pasted a tutorial." Clean config + separate depth doc reads "senior engineer who documented their work." Same content, different signal. Created `DBT_PIPELINE.md` this session as the first instance of (c).

**Comments-above-the-line, never end-of-line (2026-05-15, Phase 4 session 1)**

Same `TEACHING_PREFERENCES.md` update. End-of-line comments push lines past the Claude chat code-block width, forcing horizontal scroll which breaks reading flow. Comments-above-the-line keeps every line short, reads top-to-bottom naturally, and the file itself becomes the teaching artefact that lives in the repo forever (not just in chat scrollback). Discovered when the first verbose `dbt_project.yml` had ~120-char lines.

**dbt_project.yml vs profiles.yml — the two-file split (2026-05-15)**

dbt deliberately separates two concerns:

- **`dbt_project.yml`** says *what* to do — project name, folder layout, default materializations.
- **`profiles.yml`** says *where* to connect — Snowflake account, credentials, warehouse, database.

The bridge is the `profile:` line in `dbt_project.yml`, which looks up a matching top-level key in `profiles.yml`. One `profiles.yml` can hold multiple project profiles, each with multiple targets (`dev`, `prod`, etc.) — `dbt run --target prod` switches.

**Carry-forward.** In a team setting, every engineer has their own `profiles.yml` pointing at their personal dev schema. `dbt_project.yml` is shared and identical across the team. Don't conflate them.

**`env_var()` — dbt's secrets pattern (2026-05-15)**

```yaml
password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
```

Jinja template. At dbt-run time, the value resolves by reading the shell environment. dbt does **not** auto-read `.env` — values must already be in the OS environment when dbt starts. Result: `profiles.yml` is safe to commit (no plaintext secrets), credentials sit in `.env` (gitignored), rotation is a `.env` edit. Same pattern real teams use with HashiCorp Vault / AWS Secrets Manager — swap the secret source, dbt-side wiring is unchanged. Direct transfer to interviews: "How do you handle secrets in dbt?" → "env_var() resolving against environment populated from Vault."

**PowerShell one-liner to load `.env` before running dbt (2026-05-15)**

```powershell
Get-Content .env | ForEach-Object {
    if ($_ -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}
```

Run once per PowerShell session. Walks `.env` line-by-line, pulls out `KEY=VALUE` pairs (the regex skips comments and blank lines), sets each as a process-scoped env var. Subsequent `dbt` commands see them. Documented in `DBT_PIPELINE.md` as the prerequisite step.

**`.gitignore` un-ignore syntax (`!path`) (2026-05-15)**

Phase 0's `.gitignore` had a blanket `profiles.yml` ignore — the dbt-community default, because most teams write secrets directly into the file. We don't (we use `env_var()`), so our `profiles.yml` is safe to commit. Override syntax:

```
profiles.yml
!dbt/profiles.yml
```

A line starting with `!` un-ignores a specific path that would otherwise match a previous pattern. **Order matters** — the un-ignore must come *after* the ignore. Git evaluates `.gitignore` rules top-to-bottom, with later rules overriding earlier ones.

**Schema concatenation gotcha — dbt's default `generate_schema_name` (2026-05-15)**

dbt's default behaviour with the `+schema:` per-folder config in `dbt_project.yml` is to **concatenate** the target schema (from `profiles.yml`) with the per-folder schema. So `profiles.yml` `schema: DEV` + `+schema: staging` lands the model in `DEV_STAGING` — not the cleaner `STAGING`.

**Fix (deferred to Phase 4 session 2).** Custom `macros/generate_schema_name.sql` that overrides this — if a per-folder `+schema:` is set, use it directly without concatenating. Standard pattern in production dbt projects, deferred to before the first `dbt run` materializes anything.

For step 3d we used the existing `SNOWFLAKE_SCHEMA=RAW` env var as a placeholder — `dbt debug` doesn't materialize anything, so no harm done. Must be replaced before staging models land.

**materialized: view / table / incremental / ephemeral (2026-05-15)**

The dbt config that decides what *kind* of physical object each model becomes in Snowflake. Same SELECT, different storage strategy:

- **`view`** — `CREATE OR REPLACE VIEW`. Always fresh, no storage cost. Staging + intermediate default.
- **`table`** — `CREATE OR REPLACE TABLE`. Fast to query, slightly stale until next run. Dim tables, marts.
- **`incremental`** — `CREATE TABLE` once, then `INSERT`/`MERGE` only new rows on subsequent runs. Fact tables at scale.
- **`ephemeral`** — no warehouse object; dbt inlines as a CTE in downstream models. Tiny helpers only.

Set folder-level defaults in `dbt_project.yml` (we did), override per-model with `{{ config(materialized='...') }}`.

**Kitchen analogy that landed in session.** view = made-to-order (re-cooked every order, always fresh). table = pre-cooked buffet tray (fast to serve, stale until refreshed). incremental = topped-up buffet (existing food stays, new dishes get added). ephemeral = sauce base in the prep kitchen (never served on its own, only folded into other dishes).

**`dbt debug` as the connection canary (2026-05-15)**

No-side-effects health check — verifies `profiles.yml` resolves, env vars land, the Snowflake adapter can authenticate, and the warehouse is reachable. No models materialize. Key output: `Connection test: [OK connection ok]` + `All checks passed!`. Should be the first dbt command run after any environment change (new venv, new credentials, new shell session). Password is masked in the output even when authentication succeeds — `env_var()` works without leaking secrets to stdout.

**The grant-fix gap — Phase 2 grants didn't cover Phase 4 (2026-05-15, Phase 4 session 2)**

First `dbt build --select staging` failed mid-session with `Insufficient privileges to operate on database 'RETAIL_DB'`. The `RETAIL_ENGINEER` role provisioned in Phase 2 had everything needed to *operate inside* `RETAIL_DB.RAW` (USAGE, CREATE TABLE/VIEW/STAGE inside RAW, full DML on tables) but had never been granted `CREATE SCHEMA` at the database level. dbt's auto-create-the-STAGING-schema attempt bounced off Snowflake's RBAC.

**Root cause.** A clean miss on Criterion 7 of the 10-point audit — Upstream/downstream contract. When the dbt project landed in session 1 it expected to be able to create schemas at the DB level; we never verified the connecting role had the privilege. The Phase 2 audit was clean for Phase 2's needs (load into RAW) and didn't anticipate Phase 4's needs.

**Fix.** New `sql/snowflake/03_grant_dbt_privileges.sql` with one statement: `GRANT CREATE SCHEMA ON DATABASE RETAIL_DB TO ROLE RETAIL_ENGINEER`. Snowflake's ownership model handled the rest — once the role created STAGING, it owned STAGING, which gave it full privileges inside (CREATE VIEW, SELECT, etc.) automatically. No second-round grants needed.

**Diagnostic discipline used.** Before granting anything, ran `SHOW GRANTS TO ROLE RETAIL_ENGINEER` as ACCOUNTADMIN. Confirmed exactly what was present and what was missing. Avoided the trap of "throw more grants at it and hope." After the fix, re-ran `SHOW GRANTS` to confirm the new `CREATE SCHEMA on DATABASE RETAIL_DB` row appeared.

**Carry-forward.** Any time a new tool/layer is introduced (Power BI's connector role in Phase 5, GitHub Actions CI in Phase 6, future MERGE-into-Snowflake patterns), explicitly audit the permission boundary BEFORE the first run. The pattern is: list what the tool will attempt, list what the role currently has, identify the gap, grant once. Cheaper than mid-session firefighting. Also updated `00_provision_account.sql` to include the `CREATE SCHEMA` grant from day 1 — so a future fresh setup from this repo doesn't repeat the gap.

**Snowflake ownership model — the transitive-grants shortcut (2026-05-15)**

When a role creates a schema (or table, view, etc.), Snowflake makes that role the OWNER of the new object. Ownership in Snowflake confers full privileges automatically — no explicit `GRANT SELECT/INSERT/...` needed on the owned object. This is why granting just `CREATE SCHEMA on DATABASE` is sufficient for dbt: the role creates STAGING, becomes its owner, and can create views, run tests, drop+recreate, etc. inside it without further grants.

**Interview line.** "How do you set up Snowflake permissions for dbt?" → "Minimal grants: USAGE on warehouse and database, plus `CREATE SCHEMA` on the database. Once dbt creates each layer's schema as the connecting role, ownership covers the rest. Future grants on other roles (e.g. Power BI read-only) get added when those consumers come online."

**`{{ ref() }}` vs `{{ source() }}` — the dbt reference patterns (2026-05-15)**

Two ways for a model to point at upstream data:

- `{{ source('<source_name>', '<table_name>') }}` — references a table declared in `sources.yml`. Used in staging models pointing at RAW tables.
- `{{ ref('<model_name>') }}` — references another dbt model in this project. Used everywhere else (intermediate, warehouse, marts), AND inside staging if a staging model joins to another staging model (as `stg_m5_sales_train` does for the date translation).

Both resolve to fully-qualified `DATABASE.SCHEMA.OBJECT` strings at compile time. Crucially, `ref()` also builds the dbt model dependency graph — dbt automatically orders model builds so referenced models build first. Run `dbt run --select stg_m5_sales_train` and dbt knows to build `stg_m5_calendar` first. No manual scheduling needed.

**CTE pattern for staging models (2026-05-15)**

dbt style-guide convention for any model with more than one logical step. Three CTEs: one for each source pull, one (or more) for the actual transformation, then a final `SELECT * FROM <last_cte>`.

Three benefits:

1. Each CTE has one clear job — reads top-to-bottom like a recipe.
2. Easy to debug — swap `SELECT * FROM joined` for `SELECT * FROM source` to peek at intermediate state without rewriting the model.
3. Easy to extend — adding a new transformation step is just another CTE in the chain.

Trivial single-SELECT staging models (`stg_m5_sell_prices`) don't need this — the CTE pattern is for models that do real work.

**LEFT JOIN + `not_null` test = the join-sentinel pattern (2026-05-15)**

Defensive data engineering pattern. When joining two tables where every left row SHOULD have a match in the right (e.g. every sale day should map to a calendar entry):

- **INNER JOIN** silently drops left rows without a match. Bad — data quality issue hidden.
- **LEFT JOIN + `not_null` test** on the joined column. Mismatches produce NULL, which the test catches and surfaces as a failure. Bad data loudly visible.

Standard practice — test as observability. `sale_date NOT NULL` in `stg_m5_sales_train` is exactly this pattern.

**Schema YAML naming `_<folder>__models.yml` (2026-05-15)**

dbt convention for schema/test YAML files in a model folder. Leading underscore sorts the file to the top of the folder alphabetically. Double-underscore visually separates folder name from "models." So `dbt/models/staging/_staging__models.yml` is the canonical name. Used by dbt-labs internally and across most production projects.

**`dbt build` vs `dbt run` vs `dbt test` (2026-05-15)**

- `dbt run` — materializes models only. No tests.
- `dbt test` — runs tests only. No model rebuilds.
- `dbt build` — both, dependency-ordered. Builds a model, runs its tests, then proceeds to dependent models only if upstream tests passed. **Default for production work.** Catches data quality regressions before they propagate downstream.

The `--select <selector>` flag scopes the build (`--select staging` for one folder, `--select stg_m5_calendar+` for a model and everything downstream, etc.). Useful for iterating on one layer without rebuilding the whole project.

**dbt 1.11 `freshness` config deprecation (2026-05-15)**

`PropertyMovedToConfigDeprecation` warning surfaced on `dbt parse` of the first `sources.yml`. dbt 1.8+ moved `freshness` and `loaded_at_field` from top-level under a source to inside a `config:` block under the source. Same semantics, different nesting. Fix is small: add a `config:` key and indent everything that was at source-level by 2 spaces. Worth knowing because dbt-labs is moving toward this nested-config pattern across the board — model configs, source configs, test configs.

**`dbt_utils` install + the lockfile pattern (2026-05-16, Phase 4 session 3)**

dbt has a package system that works the same way npm and pip do for those ecosystems. Three moving parts:

- **`packages.yml`** — declares what you want. Lives next to `dbt_project.yml`. One entry per package, with a version range:

  ```yaml
  packages:
    - package: dbt-labs/dbt_utils
      version: [">=1.1.1", "<2.0.0"]
  ```

- **`dbt deps`** — the install command. Reads `packages.yml`, downloads the matching versions, drops them into `dbt_packages/`. Roughly: dbt's `npm install`.
- **`package-lock.yml`** — auto-generated by `dbt deps`. Pins the *exact* version that resolved (in our case `dbt_utils 1.3.3`). **Commit this.** Same role as `package-lock.json` or `Pipfile.lock` — guarantees that anyone else cloning the repo gets the identical package version even if `dbt_utils` ships a 1.3.4 tomorrow. `dbt_packages/` itself is gitignored (line 78), same logic as `node_modules/`.

**Why this matters in practice.** `dbt_utils` is a library of community-maintained macros that solve problems every dbt project hits — compound-key uniqueness tests, surrogate-key generation, pivot helpers, date spine generation, `not_empty_string` tests, dozens more. Installing it is one of the most universal day-1 moves in real dbt projects. The package itself is maintained by dbt-labs (the dbt company), so it's safe and stable. Same role as `pandas` for Python or `lodash` for Node — the "everyone uses this" utility library.

**The dbt 1.10+ `arguments:` syntax for generic tests (2026-05-16)**

First use of `dbt_utils.unique_combination_of_columns` on `stg_m5_sell_prices` tripped a `MissingArgumentsPropertyInGenericTestDeprecation` warning. Older dbt syntax passed macro args directly under the test name:

```yaml
- dbt_utils.unique_combination_of_columns:
    combination_of_columns: [store_id, item_id, wm_yr_wk]
```

dbt 1.10+ wants them nested under an explicit `arguments:` key:

```yaml
- dbt_utils.unique_combination_of_columns:
    arguments:
      combination_of_columns:
        - store_id
        - item_id
        - wm_yr_wk
```

Same semantics; one extra indent level. Reason: dbt is making test/config patterns uniform across the codebase, and `arguments:` signals "these are macro inputs" vs "this is dbt config." Fix is mechanical. After the edit, re-ran with `dbt build --select stg_m5_sell_prices --no-partial-parse` — the `--no-partial-parse` flag flushes dbt's cached `partial_parse.msgpack` so the deprecation cache clears. Subsequent normal `dbt build` calls are clean.

**Carry-forward.** Any new generic test or `dbt_utils` macro call writes the `arguments:` form from day 1. Old syntax still works in 1.11 but the deprecation warning is loud.

**What "parsing" means in dbt (2026-05-16)**

Before any SQL ever hits Snowflake, dbt **parses** the entire project — every `.yml` and `.sql` file under `dbt/`. Parsing builds the manifest: the dependency graph (which model `ref()`s which), all the test definitions, all the source declarations, the materialization config for every model. The manifest is what `dbt run`, `dbt test`, `dbt build` all consult to decide what to do and in what order.

**Kitchen analogy.** A chef reads through the whole recipe once before turning the stove on — checking the ingredient list is sensible, the steps reference real prep, the timings line up. That's parsing. *Then* the cooking starts. dbt does exactly that for the SQL pipeline.

**Practical consequence.** Typos and missing refs blow up at parse time, not query time. If I rename `stg_m5_calendar` to `stg_m5_cal` and forget one downstream model, `dbt parse` fails immediately with the file and line. No wasted Snowflake compute, no half-built pipeline. dbt also caches a `partial_parse.msgpack` so subsequent runs only re-parse changed files — usually sub-second. `--no-partial-parse` is the escape hatch when the cache itself gets stale (as with the deprecation-warning case above).

**The rows-back-equals-failures contract for dbt tests (2026-05-16)**

Every dbt test compiles to a `SELECT` statement. The contract is dead simple:

- Zero rows back → **pass**.
- One or more rows back → **fail**, and the rows themselves tell you exactly what failed.

A `not_null` test on `sale_date` compiles to roughly `SELECT * FROM stg_m5_sales_train WHERE sale_date IS NULL`. If the result is empty, every row has a sale_date — pass. If five rows come back, those five rows show exactly which records broke the rule. `unique_combination_of_columns` compiles to a `GROUP BY <cols> HAVING COUNT(*) > 1` — any duplicates surface as result rows.

**Why this is elegant.** No special test framework, no DSL — tests are just SQL. After any `dbt build`, you can read the literal compiled SQL Snowflake ran under `dbt/target/compiled/<project>/models/<folder>/<schema_yml>/<test_name>.sql`. Useful for "wait, what is dbt actually checking?" moments — open the file and read the query. Same idea as inspecting a compiled view in Snowsight, but for tests.

**Compound keys — the Harding's Hardware analogy (2026-05-16)**

A **compound key** (also called composite key) is a key made of multiple columns that *together* uniquely identify a row — and where none of the columns is unique on its own. `stg_m5_sell_prices` has the classic shape: `store_id` repeats (each store stocks thousands of items), `item_id` repeats (each item lives in dozens of stores), `wm_yr_wk` repeats (each fiscal week has thousands of price rows). But `(store_id, item_id, wm_yr_wk)` together identifies exactly one price row.

**The Harding's Hardware parallel.** Back in my BI-analyst days at Harding's, the stock-by-location table had the same shape: `(product_id, warehouse_id)` was the compound key. Every product appeared in multiple warehouses; every warehouse stocked multiple products; only the pair uniquely identified a stock row. Different industry, identical pattern. Compound keys show up everywhere in operational data because that's how the real world is shaped — most things are intersections.

**Why this matters for dim modelling.** Compound natural keys are the reason surrogate keys exist. Carrying `(store_id, item_id, wm_yr_wk)` through every downstream join would be three columns instead of one and would still leak source-system details into the warehouse. The dim's surrogate key (one 32-char hex string) replaces the compound natural key for join purposes. `dbt_utils.generate_surrogate_key(['store_id', 'item_id', 'wm_yr_wk'])` literally hashes the compound key into a single value.

**Intermediate layer — purpose and place (2026-05-16)**

Between **staging** (light passthrough — rename, cast, drop sentinel columns) and **warehouse** (the published Kimball star schema), there's the **intermediate** layer. Job: *business-logic joins and derivations.* This is the "workshop bench" where source-aligned shapes get assembled into business-aligned shapes before being shipped to the published star.

`int_sales_with_prices` is the textbook example. Daily sales live in one staging model, weekly prices in another, the calendar bridge in a third. None of those individually answers a business question. The intermediate model joins all three and computes `revenue_amount_usd`. Downstream `fact_daily_sales` will build from `int_sales_with_prices` rather than re-doing those joins itself.

**Why a separate layer at all.** Two reasons:

1. **Reuse.** If multiple fact tables need "sales with prices attached," the join lives once in `int_sales_with_prices` and every fact `ref()`s it. Single source of truth for that business logic.
2. **Testability.** Intermediate models get their own tests (compound-key uniqueness, NULL semantics). Without a named intermediate, the same logic is buried inside a big fact-table SELECT, harder to test in isolation.

CTE shape is the dbt-style-guide `source → enriched → final` chain. Same pattern as `stg_m5_sales_train` from session 2 — read top-to-bottom like a recipe, debug by swapping the final SELECT.

**LEFT JOIN as semantic choice, not just safe choice (2026-05-16)**

The lazy framing of LEFT JOIN is "the safe one — drops nothing, surfaces gaps as NULLs." That's true but it undersells the actual point.

In `int_sales_with_prices`, **34.66% of rows have no matching sell_price**. That's 11.4M of the 32.9M rows. Initial reaction: "huge fraction missing, must be a join problem." Then the anomaly check (Section 3 of `04_phase4_int_sales_with_prices_verification.sql`) returned **zero rows** for `units_sold > 0 AND sell_price IS NULL`. Every priceless row also has zero units sold.

**What's going on.** M5 only carries a `sell_prices` row for an item × store × fiscal week when the item is actively stocked at that store in that week. Three product-lifecycle reasons explain every NULL:

1. Product hasn't launched yet at this store (no price set yet).
2. Product is stocked in different stores within a state but not this one (inter-store assortment).
3. Product has been discontinued (no current price).

In all three cases, `units_sold = 0`. They're "product wasn't on the shelf, so it didn't sell" rows. **That's legitimate demand signal** — knowing where and when an item *wasn't* available is part of demand planning. An INNER JOIN would silently drop all 11.4M of those rows; downstream forecasts would treat "no row" as identical to "row with zero sales," which collapses two different concepts into one.

**Discipline carry-forward.** LEFT JOIN isn't a defensive default — it's the right semantic choice when the absence of a match is itself information. INNER JOIN is the right choice when an absence is a data-quality failure (e.g. the `sale_date` join sentinel from session 2). Pick consciously per join.

**Warehouse layer materialization transition — view → table (2026-05-16)**

`dim_calendar` is the first model where materialization flipped from `view` to `table`. Set by the `dbt_project.yml` per-folder defaults — staging and intermediate default to `view`, warehouse and marts default to `table`. No per-model override needed.

**Why tables for warehouse:**

- **Compute once, read many.** Power BI will hit `fact_daily_sales` and the dims thousands of times. A table is pre-materialized — Snowflake reads from storage. A view re-runs its SELECT every query. For a fact join across three dims, view-on-view-on-view would explode compute cost.
- **Stable performance.** Tables have row counts, byte sizes, and (eventually) clustering. Views are recomputed black boxes for the query planner.

**Why views for staging + intermediate:**

- **No storage cost.** Snowflake bills for storage; views are just SELECT statements saved by name.
- **Always fresh against upstream.** When Airflow lands a new day in RAW, the next query against a staging view sees it immediately. A table would need a `dbt run` first.
- **Light compute.** Staging is one-table-deep type-casting; intermediate is a couple of joins. Sub-second on Snowflake.

The transition point is `warehouse/` for exactly the right reason — that's where the data goes from "in flight" (read-once, transform-on-the-fly) to "published" (read-many, pre-built).

**Surrogate keys via `dbt_utils.generate_surrogate_key` (2026-05-16)**

```sql
{{ dbt_utils.generate_surrogate_key(['calendar_date']) }} AS date_key
```

Compiles to roughly `MD5(NVL(calendar_date::VARCHAR, '_dbt_utils_surrogate_key_null_')) AS date_key`. Output: a stable 32-character hex string. Same input always produces the same output.

**Two benefits worth the line of Jinja:**

1. **Decoupling from upstream natural-key drift.** If the source ever changes the natural key (say `calendar_date` becomes `cal_dt`, or the type changes from DATE to TIMESTAMP), the surrogate key's downstream contract holds — every fact still joins on `date_key`. Only the dim's own surrogate-key expression changes.
2. **SCD-2 readiness.** For slowly-changing dimensions (Type 2 — e.g. `dim_item` if an item's category changes over time), the same natural key needs to appear in multiple dim rows, each with its own validity window. Surrogate keys solve this trivially — each row gets a unique hash by including the validity window in the key columns. Manual `||`-concatenated keys can't do this cleanly.

`dim_calendar` only needs one column in the key list (`calendar_date`), but the macro accepts a list specifically so compound surrogates work: `generate_surrogate_key(['store_id', 'item_id', 'wm_yr_wk'])` for a dim whose natural key is compound.

**ISO date variants in Snowflake — session-parameter independence (2026-05-16)**

`dim_calendar` derives `day_of_week` and `week_of_year` from `calendar_date` directly rather than carrying through M5's pre-computed `wday` / `wm_yr_wk` columns. The function choice matters:

- `DAYOFWEEKISO(calendar_date)` → 1–7 with **Monday = 1, Sunday = 7**. ISO 8601 standard. Doesn't change.
- `DAYOFWEEK(calendar_date)` → 0–6 by default, with the starting day controlled by Snowflake's session-level `WEEK_START` parameter. Different account, different default — different answer for the same date.
- `WEEKISO(calendar_date)` → ISO 8601 week number, same definition everywhere.
- `WEEK(calendar_date)` → controlled by `WEEK_OF_YEAR_POLICY`. Different per environment.

**Why this matters for a dim.** Dims get queried by every downstream model, by Power BI, by ad-hoc analysts, possibly from sessions with different parameter settings. If the dim's own values flip based on whose session you're in, the analytics aren't reproducible. ISO variants are fixed by international standard — same answer everywhere, forever.

Same discipline applied to `is_weekend`: derived via `DAYNAME(calendar_date) IN ('Sat', 'Sun')` rather than a numeric `DAYOFWEEK` check. `DAYNAME` returns three-letter English abbreviations regardless of session locale — convention-independent.

**Carry-forward.** Any time a derivation could behave differently based on session state, prefer the variant that's pinned to an external standard (ISO, English abbreviations, UTC, etc.).

**The NULL-vs-empty-string trap — implicit verification (2026-05-16)**

`is_holiday` in `dim_calendar` is computed as:

```sql
CASE
    WHEN event_name_1 IS NOT NULL OR event_name_2 IS NOT NULL
    THEN TRUE
    ELSE FALSE
END AS is_holiday
```

Classic SQL trap: `'' IS NOT NULL` evaluates to **TRUE** in every major dialect — an empty string is not the same as NULL. If M5's source had loaded "no event" rows with `event_name_1 = ''` instead of `event_name_1 = NULL`, `is_holiday` would have been TRUE on every single non-event day. The whole flag would be useless.

**The eyeball check in Section 2 of `05_phase4_dim_calendar_verification.sql` implicitly verified this.** A random Friday with no event in the source returned `is_holiday = FALSE` correctly. That can only happen if the underlying `event_name_1` value is a genuine NULL, not an empty string. No explicit "is this NULL or empty string" assertion needed — the boolean output already settled it.

**Why I'm flagging this.** I almost wrote `event_name_1 != ''` as a defensive variant of the condition. Would have been wrong on a clean source (where the empty-string case never occurs) and right on a dirty source (where mixed NULLs and empty strings would otherwise sneak through). The correct discipline for staging+: explicitly normalize empty strings to NULL during cast (`NULLIF(event_name_1, '') AS event_name_1`) so every downstream model can trust `IS NULL` semantics. Already a discipline rule going forward; M5's source is clean so it doesn't bite here, but the next source might be dirtier.

**Date-spine pattern — production `dim_calendar` is procedurally generated (2026-05-16)**

`dim_calendar` currently has 1,079 rows, covering **2011-01-29 to 2014-03-21 with gaps**. The latest date (2014-03-21) is wrong relative to the planned cutoff of 2014-01-04 — leftover from a Phase 2 smoke-test extract that pulled a wider window. More importantly: the dim covers only what's been extracted to RAW, with the same gaps that RAW has.

**That's not how production `dim_calendar` typically works.** A production date dimension is **procedurally generated** — a continuous spine from some start date (e.g. 2010-01-01) to some end date (e.g. 2030-12-31), independent of what facts have landed. Why: Power BI and downstream BI tools assume the dim is continuous when drawing time-series axes. If a date with zero sales is missing from `dim_calendar`, Power BI's x-axis skips it entirely — a 14-day gap shows as a continuous line, not a flat segment. Procedural generation guarantees every date exists whether or not a fact row references it.

**Standard pattern.** Use `dbt_utils.date_spine()` macro — generates a continuous date range as a CTE, no source table needed. Then LEFT JOIN any source-derived attributes (like `wm_yr_wk` or `event_name_*`) onto the spine.

**Flagged for Phase 6 polish or Project 3.** Current `dim_calendar` works for the analytics this project will surface (M5 is a complete daily-grain dataset for the dates it covers — there genuinely are no missing dates within the 2011-01-29 to 2014-03-21 window once the full backfill is loaded). But the discipline rule — *dimensions are independent of fact coverage* — is worth recording now.

**Phase-boundary structural audit — caught real findings on first use (2026-05-16, Phase 4 session 4)**

Added a new section to `CODE_QUALITY.md` formalising a check that's distinct from the per-script 10-point audit: a **structural pass over the project's file inventory** at each phase or layer boundary. The per-script audit verifies that individual files meet the bar; the structural audit verifies that the collection of files as a whole is internally consistent — no naming collisions, no stale scaffolding, no missing pairings, no test-count drift between schema YAMLs and `dbt build`.

First explicit application caught two real issues: (a) two verify files both prefixed `04_` (`04_phase4_staging_layer_verification.sql` from session 2 colliding with `04_phase4_int_sales_with_prices_verification.sql` from session 3), renamed the latter to `04a_`; (b) three stale `.gitkeep` placeholders in `staging/`/`intermediate/`/`warehouse/` model folders despite those folders now containing real models, deleted them. Both 30-second fixes in-session; both would have been frozen into the session commit otherwise.

**Discipline rule going forward:** end-of-phase structural pass before drafting closeout docs and before the bundled commit. Cheap to run, pays for itself the first time it catches drift.

**Incremental materialization on Snowflake — the `is_incremental()` Jinja guard (2026-05-16)**

`fact_daily_sales` is the first model in the project materialised as `incremental` rather than `view` or `table`. The pattern uses dbt's built-in `is_incremental()` macro to wrap a WHERE clause that only fires on builds *after* the first:

```sql
{% if is_incremental() %}
    WHERE sale_date > (SELECT COALESCE(MAX(sale_date), '1900-01-01') FROM {{ this }})
{% endif %}
```

First build: this block is skipped → full 32.9M-row historical load. Subsequent builds: only rows newer than the current max `sale_date` enter. The `COALESCE` handles the edge case where the table exists but is empty (rare, but real — partial-failure recovery).

`unique_key='sale_key'` plus the Snowflake default `incremental_strategy='merge'` means dbt does an UPSERT — new rows insert, existing keys update. Safe even if a re-run overlaps a previously-processed date.

**Snowflake clustering — the BigQuery-partition equivalent (2026-05-16)**

Snowflake doesn't have explicit partitions like BigQuery. It has **automatic micro-partitions** (50–500MB compressed slices that the engine manages) and an optional **clustering key** that tells Snowflake how to physically co-locate rows when re-organising those micro-partitions.

`cluster_by=['sale_date']` on `fact_daily_sales` is the equivalent of `PARTITION BY sale_date` in BigQuery: tells Snowflake to keep rows with adjacent `sale_date` values in the same micro-partitions, so date-range queries (the dominant access pattern for a fact table) skip irrelevant micro-partitions and scan less data. Clustering happens automatically in the background — no maintenance commands needed.

**Compute-same-way FK keys vs JOIN-to-dims (2026-05-16)**

Two patterns for wiring fact-table FKs to dimension PKs:

- **JOIN-to-dim** — classical Kimball pattern: `LEFT JOIN dim_item ON fact.item_id = dim_item.item_id` and pull `dim_item.item_key` out. Pros: explicitly validates referential integrity row-by-row at build time. Cons: three joins × 32.9M rows = expensive; if any FK is missing in a dim, the row gets a NULL key without raising an error.

- **Compute-same-way** — call `dbt_utils.generate_surrogate_key(['item_id'])` on both sides. Same input → same MD5 → matching key by construction. No joins. Pros: cheap (no row-by-row JOINs), can't get a NULL key. Cons: doesn't enforce dim coverage at build time — needs a separate `relationships` test to catch orphan FKs.

`fact_daily_sales` uses compute-same-way + three `relationships` tests. The tests caught zero orphans across 32.9M rows in <0.5s each, so the contract is enforced even though we never JOIN. Cheaper at scale, and the test result is the same kind of contract assurance.

**`relationships` test performance on 32.9M rows — sub-second (2026-05-16)**

Three FK `relationships` tests on `fact_daily_sales` (against `dim_item`, `dim_store`, `dim_calendar`) each completed in **under 0.5 seconds** during `dbt build`. That's checking 32.9M × 3 = ~99M FK lookups against dim PKs.

Why so fast: Snowflake's query optimiser sees the test query (`SELECT COUNT(*) FROM fact f WHERE NOT EXISTS (SELECT 1 FROM dim d WHERE d.key = f.key)`) and resolves it as a hash join with the dim's PK in memory. Dims are 1k–3k rows — fits comfortably in a single warehouse XS slot. The optimiser does the heavy lifting; nothing tuning-side needed from us.

Worth knowing because the instinct from row-store databases is "relationships tests on large facts will be slow." On Snowflake (and any columnar warehouse with a half-decent optimiser), they're cheap.

**`dbt_utils.accepted_range` — column-level range assertion (2026-05-16)**

Added `accepted_range` test on `fact_daily_sales.units_sold` with `min_value: 0, inclusive: true` to codify the constraint "no negative units." Verify Section 4 had already confirmed `MIN(units_sold) = 0` empirically, but a dbt test makes the contract machine-enforced rather than human-spotted.

`accepted_range` reads cleaner in test output than the alternative `dbt_utils.expression_is_true` with `expression: 'units_sold >= 0'`. Both work; the range version is dbt-idiomatic for "this column's values are within a range."

**`MissingArgumentsPropertyInGenericTestDeprecation` re-encountered — second time same lesson (2026-05-16)**

Same dbt 1.10+ deprecation we caught in session 3 on the compound-key test. Session 4 hit it again — three occurrences this time, all on the new `relationships` tests in `_warehouse__models.yml`. The fix is identical: wrap the test arguments in an `arguments:` block.

Same pattern, second hit. **Discipline rule reinforced**: every new generic test (any test whose name has a `.` like `dbt_utils.unique_combination_of_columns` or `relationships`) needs the modern `arguments:` wrapping from the start. Treat the deprecation as if it were an error — fix it on first write, not after the deprecation warning surfaces.

**`dim_item` design — no string parsing needed (2026-05-16)**

`PROJECT_CONTEXT.md` had originally noted that `dim_item` would "derive department/category from `item_id` structure (M5 item_ids are `<DEPT>_<CAT>_<NNN>`)." When it came time to actually build it, a check of `stg_m5_sales_train` showed `dept_id` and `cat_id` already shipped as their own columns from M5's source CSV.

Chose `SELECT DISTINCT item_id, dept_id, cat_id FROM stg_m5_sales_train` over splitting `item_id` strings with `SPLIT_PART` or regex. Cleaner: no parsing logic to maintain, no risk of getting the regex wrong, no surface area for "what if the format changes in a future load."

**Lesson**: "derive from structure" should be the *fallback* when the data doesn't ship the columns separately. If staging already has them, take them directly. The plan note from earlier was a guess about what would be needed; check what the data actually has before writing parsing code.

**Two-CTE pattern when there's nothing to derive (2026-05-16)**

`dim_calendar` had a three-CTE shape (`source → enriched → final`) because it derived 10+ new columns (year, quarter, month, day_name, is_weekend, is_holiday, etc.). `dim_item` has nothing to derive — every column comes through unchanged from staging. Dropped the `enriched` middle CTE; the shape is just `source → final`.

**Lesson**: don't add an empty pass-through CTE for symmetry. CTE structure should reflect what the model is *doing*, not pattern-match a previous model. Two-CTE for derivation-free dims, three-CTE for dims that compute attributes. The reader should be able to look at the CTE list and infer what work is happening at each step.

**MD5 surrogate consistency across the star schema (2026-05-16)**

The four warehouse models all use `dbt_utils.generate_surrogate_key()` with the same inputs on both sides of every FK relationship:

| Fact column | Dim PK column | Both compute |
| --- | --- | --- |
| `fact_daily_sales.item_key` | `dim_item.item_key` | `MD5(item_id)` |
| `fact_daily_sales.store_key` | `dim_store.store_key` | `MD5(store_id)` |
| `fact_daily_sales.date_key` | `dim_calendar.date_key` | `MD5(sale_date)` (== `calendar_date`) |
| `fact_daily_sales.sale_key` | (none, fact's own PK) | `MD5(item_id, store_id, sale_date)` |

Same MD5 input → same 32-char hex output, deterministically. FK-PK matching is by construction — no need to JOIN-and-lookup at build time. The `relationships` tests catch any drift if a dim is rebuilt with different inputs (defence-in-depth).

**Lesson**: surrogate-key hashing is its own integrity mechanism in a star schema *if* the inputs are identical both sides. Always hash the natural key, not a derived value; never hash all columns. Documented this in `dim_item.sql`'s short header so the next person reading the model sees the contract.

**First full-DAG `dbt build` after incremental fact — 15.26s no-op rebuild (2026-05-16)**

After the initial full-load build of `fact_daily_sales` (~22s for 32.9M rows + 12 tests), the next full-DAG `dbt build --no-partial-parse` ran the entire project in **15.26 seconds**. PASS=66 (1 incremental + 3 tables + 4 views + 58 data tests), WARN=0, ERROR=0.

Why so fast: the incremental's `is_incremental()` block evaluated to "no new dates beyond 2014-03-21" → MERGE found zero new rows → near-instant. The three dims (table materialisations) re-ran fully but they're 3k / 10 / 1k rows. Views are query definitions, not materialisations. Tests are the slow line items.

**The interview talk-track**: "End-to-end retail star schema with 32.9M-row fact, 58 tests, full DAG re-validation in 15 seconds." That's the headline for "show me a dbt project on your portfolio." Cheap to demonstrate, easy to explain why each line of the architecture is the way it is.

**Headline portfolio numbers worth carrying through (2026-05-16)**

Captured for interview / portfolio README closing slides:

- **32,898,710 fact rows** in `fact_daily_sales` (~33M)
- **$93,559,341.40 total revenue** across the M5 dataset
- **3,049 items × 10 stores × ~1,148 days** of coverage (2011-01-29 to 2014-03-21)
- **0 orphan FKs** across three `relationships` tests
- **58 dbt tests** across the project, full DAG green in 15.26s
- **34.66% NULL price rate** in the fact (M5 product lifecycle — items not on sale every week)

These are real numbers from a real pipeline. The 32.9M / $93.5M scale-of-data signal is the kind of detail that elevates a portfolio repo from "I followed a tutorial" to "I built and validated a production-shaped pipeline."

### 2026-05-17 — Mart-layer aggregation patterns

Four idioms applied in `mart_executive_overview` worth knowing for any future mart:

**1. `SUM` semantics on a nullable measure.** ANSI `SUM()` ignores NULLs by default. `revenue_amount_usd` is NULL on ~34.66% of fact rows (M5 product-lifecycle gaps); `SUM(revenue_amount_usd)` skips those and totals only the priced ones. Right semantic — rows with unknown revenue contributing zero beats rows defaulted to `0` and silently understating the day. The interview-friendly version: *"a NULL price means we don't know the revenue, not that the revenue was zero; SUM respects that automatically."*

**2. `CASE`-inside-`COUNT(DISTINCT ...)` for filtered distinct counts.** Cleaner and cheaper than the subquery alternative. The CASE emits the id only when the condition fires (NULL otherwise); `COUNT(DISTINCT ...)` skips NULLs. Snowflake resolves the whole expression in one pass — no subquery, no second scan. Pattern is general and applies wherever "count distinct things matching X" is needed.

**3. `accepted_range` upper bounds tied to dim cardinalities.** `active_item_count` capped at 3,049 (the M5 item count); `active_store_count` capped at 10 (the M5 store count). These caps make a category of grain bug (accidental cross-join, key explosion, fan-out from a botched join) machine-detectable. If the test ever fires, something is fanning out the fact's grain — not a downstream display bug. Cheap insurance.

**4. `not_null` on an aggregate of a nullable column.** Counter-intuitive but correct: `revenue_amount_usd` is nullable at the fact level (correct — M5 lifecycle gaps), but `total_revenue_usd` at the mart level is `not_null`-tested. Reasoning: a NULL daily total would mean every row in the day's fact has NULL price, which is a catastrophic upstream condition — should fire as a test failure, not show as a blank cell in Power BI.

**Carry-forward to Project #3:** when adding any aggregation layer above a nullable measure, ask "what does NULL at the aggregate level mean for the downstream consumer?" — if the answer is "they'd be confused or take a wrong action," codify `not_null` at the aggregate level even if the source column allows NULL.

### 2026-05-17 — dbt-core and adapter version pinning (1.8+ decoupling)

First attempt to pin both `dbt-core` and `dbt-snowflake` to `1.11.5` in the Airflow image's dbt venv failed with `pip ResolutionImpossible`:

```
The user requested dbt-core==1.11.5
dbt-snowflake 1.11.5 depends on dbt-core<2.0 and >=1.11.6
```

**Root cause**: since the **dbt 1.8 release**, dbt-core and the adapters (`dbt-snowflake`, `dbt-postgres`, `dbt-bigquery`, etc.) ship on **independent patch cycles**. The version numbers between core and adapter don't have to match; in this case the adapter explicitly requires a newer patch than its own version number.

**Fix**: pin both exactly, but to different patches:

```
dbt-core==1.11.10 dbt-snowflake==1.11.5
```

`dbt-core==1.11.10` is the latest 1.11.x patch and was what pip resolved to on its own when only the adapter was pinned (without an explicit dbt-core pin). Documented in the Dockerfile comment so future engineers reading the repo understand why the numbers diverge.

**Carry-forward**: when pinning dbt versions, don't assume `1.X.Y` adapter requires `1.X.Y` core. Check the adapter's PyPI metadata (or `setup.py`) for its `dbt-core` requirement range, then pin accordingly. Document the divergence inline so a future reader doesn't waste time wondering why the numbers don't match.

### 2026-05-17 — Incremental fact backfill limitation in `is_incremental()` patterns

Caught at trigger time during end-to-end testing. The first manual trigger (logical_date `2014-01-05`, processing date `2014-01-04`) failed at `verify_dbt_one_day` with the fact and mart showing 0 rows for the run date. Diagnosis:

The fact uses the standard incremental pattern:

```sql
{{ config(materialized='incremental', unique_key='sale_key') }}

SELECT ... FROM {{ ref('int_sales_with_prices') }}
{% if is_incremental() %}
WHERE sale_date > (SELECT MAX(sale_date) FROM {{ this }})
{% endif %}
```

The fact's current `MAX(sale_date) = 2014-03-21` (from the session 4 initial build). When staging data for 2014-01-04 (the `ds` for logical_date 2014-01-05 in `@daily` semantics) flowed through the new build, the WHERE clause `sale_date > '2014-03-21'` excluded it — the MERGE inserted 0 new rows for 2014-01-04, and the mart aggregating from the fact also got 0 rows for that date.

**The structural lesson**: `WHERE sale_date > MAX(sale_date)` patterns **extend forward only**. They cannot **backfill** historical dates within the existing range. Two ways to handle backfill use cases:

1. `dbt run --full-refresh --select fact_daily_sales` — rebuilds the whole fact from scratch (expensive for large facts but correct).
2. A date-window incremental variant: `WHERE sale_date BETWEEN {{ var('start_date') }} AND {{ var('end_date') }}` — allows targeted backfill of a specific window via `dbt run --vars '{start_date: 2014-01-01, end_date: 2014-01-31}'`.

For our test trigger, the practical fix was to pick a date **after** the current fact max (logical_date 2014-03-23 → ds 2014-03-22 → incremental filter accepts it). For real backfill scenarios, the full-refresh path is what we'd use.

**Carry-forward**: design the incremental's WHERE clause around the actual use case. Forward-only is fine for "extract today, add tomorrow" patterns; date-window is required if you ever need to backfill arbitrary historical dates without a full refresh. Document the choice in the model's header comment so future maintainers understand the design intent.

### 2026-05-17 — Failure injection as a validation technique

To prove the four-task chain halts cleanly on a dbt test failure, deliberately broke the mart's `active_store_count` `accepted_range` test (flipped `max_value: 10` → `5`). Triggered a fresh run for a new logical date. Observed exactly the predicted behaviour:

- `extract_one_day` → green
- `verify_one_day` → green
- `dbt_models` task group → 8 model `run` + `test` pairs green, then `mart_executive_overview.test` → **red** (the broken test fired across essentially every row of the rebuilt mart and failed). Task group status: red overall.
- `verify_dbt_one_day` → **upstream_failed**, duration `00:00:00`, never executed
- Overall DAG run → failed

Reverted the YAML edit post-test so the project state is clean.

**Why this works as a testing pattern**: a temporary YAML flip is **fully reversible** (no DDL changes, no orphaned data) and exercises the failure-handling code paths in the orchestrator. The success path was already proven in the prior run (2014-03-22 → all four task squares green), so the asymmetric pair "happy path passes, then break one test → confirm chain halts" demonstrates both directions cleanly. Clean revert is part of the technique — never commit a broken-test YAML.

**Carry-forward**: use failure injection as a closing validation step whenever wiring up an orchestration chain. Flip one value, trigger, observe the clean halt, revert. Especially valuable for portfolio purposes because it produces a credible "yes, the failure path actually works" screenshot pair.

### 2026-05-22 — Airflow `schedule=None` is the correct pattern for portfolio-demo DAGs

Surfaced during Phase 5 session 5.9 end-to-end smoke test. Original DAG was declared with `schedule="@daily"` + `catchup=False` — the conventional "scheduled production cron" pattern. On unpausing the DAG to recover from a pause-mid-run trap (see next entry), Airflow's scheduler immediately auto-created a DagRun for the most recent missed scheduled interval — which for a 2026 wall-clock run meant a DagRun with `logical_date` ≈ today's date. That DagRun then tried to extract M5 data for 2026-05-22, which doesn't exist in Azure SQL (M5 dataset ends ~2016), and failed at `extract_one_day`.

**Why this is wrong for a portfolio-demo DAG**: a portfolio project's DAG should only ever run when the operator triggers it on command. Running automatically on unpause produces phantom DagRuns that the operator never asked for, complicates the run-history narrative (extra red squares in the UI), and creates a Snowflake compute cost we didn't intend. The "scheduled production cron" framing is the wrong framing for a project that exists to demonstrate the orchestration pattern, not to run on a real ops cadence.

**The fix**: change the `@dag` decorator's `schedule="@daily"` → `schedule=None`. With `schedule=None`, the Airflow scheduler never auto-creates a DagRun. The only way to run is via UI "Trigger DAG w/ config" with an explicit logical date, or via CLI `airflow dags trigger` / `airflow dags test`. Pause/unpause becomes a near-no-op (still controls whether scheduler queues tasks within existing DagRuns, but no longer drives DagRun creation at all).

**Pattern decision criteria**:

- **`schedule="@daily"` (or any cron) + `catchup=False`**: use when you have a real ops cadence (a database that genuinely emits new data daily and you want Airflow to fetch it automatically). Accept the discipline that unpausing creates a DagRun.
- **`schedule=None`**: use for portfolio-demo DAGs, ad-hoc backfill DAGs, manual-only orchestration scenarios. Operator controls every DagRun explicitly. No phantom runs ever.
- **`schedule="@daily"` + `catchup=True`**: use when historical backfill on first start is intentional (e.g., onboarding a new source where you want every missed day backfilled). Almost never the right default — explicit opt-in only.

**The `catchup=False` flag is still kept in code** even with `schedule=None`, as a belt-and-braces signal of intent: even if someone later changes the schedule back to `@daily` for some reason, catchup=False prevents the 12-year backfill cliff. Defense-in-depth costs nothing.

**Portfolio narrative shift**: pivoting from `@daily` to `None` doesn't weaken the interview story — it strengthens it. "I built this DAG with `schedule=None` so the operator controls every run; the date-partitioned extract pattern works because every DagRun gets a logical_date via config, and the extract task reads `context['ds']` to pull the right slice. Production deployment would flip this to a real cron schedule, but for a portfolio-demo where I want a single repeatable run on command, schedule=None is correct." That's a senior-engineer architectural framing.

**Carry-forward for Project #3**: default new orchestration DAGs in portfolio projects to `schedule=None`. Only set a real cron schedule when there's a real ops cadence requirement. Document the choice explicitly in the DAG docstring so a future reader sees the intent immediately.

### 2026-05-22 — Airflow pause-mid-run trap: paused DAGs strand tasks in "scheduled" state

Surfaced during Phase 5 session 5.9 end-to-end smoke test. After triggering a manual DagRun (smoke_test_5_9_2014_03_24) on a paused DAG via "Trigger DAG w/ config", the first task `extract_one_day` ran to completion (green). The second task `verify_one_day` then transitioned to `scheduled` state and **stayed there for 12+ minutes** — well outside the normal 5-30 second scheduled→queued transition window. The third and fourth tasks never started.

**Root cause**: in Airflow 2.x the scheduler only evaluates tasks for DAGs whose `is_paused` flag is False. Tasks already in `running` or `queued` state when a DAG is paused will continue to run to completion (which is why `extract_one_day` finished green — it was already queued before the pause). But tasks that need to transition from `scheduled` → `queued` after the pause **get stranded**: the state-machine creates the `scheduled` task instance based on dependency satisfaction (upstream tasks succeeded), but the scheduler refuses to push `scheduled` → `queued` because the DAG is paused. The run is alive, the dependency is satisfied, the task is sitting there waiting — but no worker will ever pick it up until the DAG is unpaused.

**The asymmetric pause behavior**:

- Already-queued / already-running tasks: continue to completion ✓
- Tasks that need to be queued after the pause: stranded forever ✗

This is documented Airflow behavior, not a bug. See [Airflow Issue #15439](https://github.com/apache/airflow/issues/15439) — "DAG run state not updated while DAG is paused" — and the related discussion in [#55675](https://github.com/apache/airflow/issues/55675).

**The fix when this happens**: unpause the DAG. The scheduler will pick up the stranded task within ~30 seconds and the rest of the chain proceeds normally.

**The discipline rule to avoid this entirely**:

- **NEVER pause a DAG mid-run if you want the run to complete.** Pausing is for "stop creating new DagRuns", not for "freeze the current run". The pause toggle is a scheduler-control, not a run-control.
- **If you only want a one-off run, the safe sequence is: (1) unpause if necessary, (2) trigger the DagRun, (3) let it run to completion, (4) THEN pause.** Reversing steps 3 and 4 strands the chain.
- **For genuinely paused-by-default DAGs, use `schedule=None`** (see prior LEARNING) so unpausing doesn't auto-create phantom runs and the pause/unpause cycle becomes much less load-bearing.

**The asymmetric trap also has implications for the "Unpause DAG when triggered" toggle** in the "Trigger DAG w/ config" dialog. The toggle's label suggests it controls whether the DAG gets unpaused on trigger, but its effective semantics interact with the asymmetric pause behavior in non-obvious ways. In 5.9 we observed that even with the toggle set off (visually grey), the DAG ended up unpaused after trigger — possibly an Airflow 2.10.3 behavior where manual triggers always unpause regardless of toggle state. Safest practice: don't rely on the toggle for pause-control; instead, manually pause AFTER the run completes if you want the DAG paused.

**Carry-forward for Project #3**: when designing orchestration DAGs, document the pause-mid-run trap in the DAG docstring or in the project's orchestration runbook. New analysts pairing on the project will hit this if they pause a DAG before its current run completes, and the symptom (task stuck on "scheduled" indefinitely) looks like a worker failure or a scheduler hang rather than a pause-state issue.

### 2026-05-22 — Stale variable references in surgically-modified functions: scan return strings + log calls when removing a check

Surfaced during Phase 5 session 5.9 smoke test. In Phase 5.4 the `verify_dbt_one_day` task in `airflow/dags/m5_daily_extract.py` was modified to remove the mart-layer check (the legacy `MART_EXECUTIVE_OVERVIEW` was renamed to `AGG_SALES_DAILY` with a different key schema; the per-run mart row-count check became redundant because `fact_daily_sales` already validates the incremental MERGE). The check itself was removed cleanly from the SQL query, the binds, the unpack, the log calls, the failure-check block — **but the success-path return statement still contained `f"fact={fact_rows}, mart={mart_rows}"`**, where `mart_rows` was no longer defined. The bug sat undiscovered for ~6 sessions because:

- The 5.4 backfill ran with a feature-flag path that didn't reach this code,
- Subsequent runs all failed earlier in the chain on unrelated issues (Snowflake transients, schema drift), masking the bug,
- No CI / unit tests on Airflow task functions to catch the NameError statically.

The bug fired on the 5.9 smoke test as the first run that actually reached the success path of `verify_dbt_one_day` since the 5.4 modification. Symptom: extract green, verify_one_day green, dbt_models all green, verify_dbt_one_day **red** with `NameError: name 'mart_rows' is not defined`.

**The discipline rule**: when surgically removing a check or a variable from inside a function, scan for ALL references to the removed name in the rest of the function body — not just the obvious ones. Specifically:

1. The SQL query itself (obvious).
2. The bind tuple passed to `cur.execute()` (often forgotten).
3. The unpacking line that destructures the row (often forgotten).
4. **The log calls — `log.info(...)` lines that include the removed variable in their format args** (often forgotten because log statements look like side-effects, not code paths).
5. **The success-path return string — f-strings or `.format()` calls that include the removed variable** (the 5.9 bug — easiest to miss because the return is at the bottom of the function, far from the check-block where the variable was used).
6. The failure-check block — any `if x <= 0: failures.append(...)` lines (obvious, usually caught).

**Why the success-path return is the easy-to-miss case**: when checks fail, the function raises before reaching the return. When checks pass, the return executes and the NameError fires. So the bug only surfaces on the happy path — exactly the path that hasn't been exercised since the modification, exactly the path you'd assume is "obviously working" because the data layer is healthy.

**Defense-in-depth practices to catch this earlier**:

- **Static analysis**: a `ruff` or `flake8` lint pass with `F821 undefined-name` enabled would catch this in <1 second. Worth adding to the project's CI as a pre-merge gate.
- **`mypy --strict` or similar type-checking**: would also catch undefined references, plus catch type-mismatch bugs.
- **End-to-end smoke tests as a phase-close gate**: the 5.9 smoke test is exactly how this bug was found. Every phase that modifies an Airflow DAG should close with one fresh end-to-end DagRun, not just unit tests of individual task functions.
- **Code review checklist item**: "when removing a variable or a check, search the whole function body for references to the removed name before merging".

**Carry-forward for Project #3**: add `ruff` (or equivalent) to the CI pipeline with `F821` enabled, as a pre-merge gate on any `*.py` file in `airflow/dags/`. Also bake the end-to-end smoke test as a phase-close ritual — the cheapest, highest-signal validation step at the end of each phase.

### Power BI (advanced from Project #1)

### 2026-05-18 — Explicit DAX measures over implicit aggregations

Phase 5 session 1 discipline rule, locked from the first Card on the Executive Overview page. Every measure displayed on the dashboard is a named DAX measure (`Total Revenue`, `Total Units Sold`, `Active Items`, `Active Stores`), not a column dragged onto a visual with PBI's default Σ aggregation.

**The difference**: dragging `MART_EXECUTIVE_OVERVIEW[total_revenue_usd]` directly onto a Card creates an **implicit measure** — an unnamed throwaway `SUM()` that exists only inside that one visual. Five visuals using the same column = five separate throwaway aggregations, none named, none reusable, format settings applied per-visual.

A **named DAX measure** is the recipe written down once in the head office. Every Card / chart / tooltip / DAX-derived measure that references "Total Revenue" points back to one definition. Change the recipe centrally — formatting, underlying column, even the aggregation type — and every visual everywhere updates next render.

**Recipe-on-the-wall analogy**: implicit measures are chefs cooking "tomato sauce" from memory at every station — slight variations creep in, and if you want to change the recipe you retrain every chef individually. Explicit measures hang the recipe on the wall once; every kitchen reads from it.

**One concrete future-payoff** this enables: time intelligence DAX in session 5.5 (`Total Units Sold YoY`, `Total Units Sold YTD`, `Total Units Sold MTD`) are written as new measures that reference `Total Units Sold` as their base. Like sauces that start with the base tomato recipe. If the base were a throwaway implicit aggregation, every derived measure would have to recreate the base sum inside itself — and any later refactor would touch every derived measure. With the base measure named, the derived measures stay clean.

**Discipline rule for the rest of Phase 5**: every measure used on any visual is created as a named DAX measure via `New measure` first, then referenced. Implicit aggregations (drag-the-Σ-column) are a red flag in code review. Default project-wide.

### 2026-05-18 — Mart→calendar 1:1 cardinality override for star-schema discipline

Hit during the semantic model build in Phase 5 session 1. `MART_EXECUTIVE_OVERVIEW.sale_date` (1,081 unique daily rows) and `DIM_CALENDAR.calendar_date` (1,082 unique dates) connected via drag-and-drop in Model View. PBI auto-detected the cardinality as **One to one (1:1)** because both columns are unique on their respective tables. PBI then **locked the cross-filter direction to "Both"** — no Single option available, no way to override.

**Why "Both" is wrong for this model**: both `FACT_DAILY_SALES` and `MART_EXECUTIVE_OVERVIEW` connect to `DIM_CALENDAR`. With bidirectional cross-filter from mart→calendar, filtering on the mart would cascade *through* `dim_calendar` *into* the fact (because dim→fact has its own filter). Suddenly the mart could filter the fact, which is not the star-schema intent and creates hidden filter chains that produce wrong DAX results later.

**The fix**: manually **override the cardinality dropdown to "Many to one (*:1)"**. PBI shows a benign yellow warning along the lines of *"data integrity may be at risk — unique values detected on both sides"* — accept it. Cross-filter direction then unlocks; set to **Single**.

**Why this is semantically correct even though the data is technically 1:1**: `dim_calendar` is the **conformed dimension** (single source of truth for date attributes — day name, holiday flag, ISO week). The mart is **downstream consumption** of fact data. As new dates land in `dim_calendar` ahead of the mart catching up (e.g. when extract runs but dbt hasn't rebuilt the mart yet), the constraint stays valid as many-to-one. The 1:1 is degenerate in current state, not in design.

**Discipline rule banked**: every relationship from a fact or mart to a conformed dimension should be many-to-one with Single cross-filter direction, regardless of current uniqueness on both sides. Star-schema purity > technical accuracy.

### 2026-05-18 — Power BI dual-axis line charts disable trend lines

Discovered when trying to add trend lines to the Executive Overview revenue + units chart. The chart auto-converted to **dual-axis** when both measures were added to the Y-axis (Total Revenue $40K–$140K range on left axis, Total Units Sold 0K–50K range on right axis — PBI detects scale-difference and splits axes).

In the Analytics pane (the magnifying-glass icon in Visualizations), the available options were: X/Y-Axis Constant Line, Min line, Max line, Average line, Median line, Percentile line, Error bars, Anomalies. **No "Trend line" option.**

**Why**: PBI's trend-line feature requires a single-axis chart with a date/continuous X-axis. Dual-axis combo charts are excluded by design — a single trend line over two different scales would be ambiguous, and per-series trend lines aren't supported in this chart type.

**Workarounds**:
1. **Split into two single-measure side-by-side charts.** Each chart then has one Y-axis and supports its own trend line via Analytics. Most professional fix for a polished portfolio dashboard.
2. **Use Min/Max/Average lines as proxies.** Available on dual-axis charts; not a real trend (no slope), but useful for "threshold" or "baseline" annotations.
3. **Switch to a "Line and clustered column" combo chart** with explicit primary + secondary axes. Different constraints; some versions allow trend on the primary line.

**Banked for Phase 5 session 5.6** (polish pass): if trend lines are wanted for the Home page, split the dual-axis chart into two single-measure charts. Until then, the dual-axis story is clean enough.

**Carry-forward**: PBI's Analytics pane offerings change based on visual type and configuration. Before promising a feature to a stakeholder, check what's actually available in the current chart state.

### 2026-05-18 — Power BI Desktop UI version variance + web-check discipline

Earned by being wrong about it twice during Phase 5 session 1. Power BI Desktop **ships continuous UI updates** — visuals get promoted from preview to default, old ones get hidden, ribbon items move between sections, dialog field labels change. The mental model of "PBI Desktop has X feature in Y location" goes stale fast.

**Concrete examples from this single session**:
- **"Recent Sources"** in Get Data dropdown — visible in some versions, absent in Phil's. Not a paid-vs-free distinction (Power BI Desktop is universally free); just a version difference.
- **Data-load progress modal** — shows a row counter in some versions, just a spinner in Phil's. Same version-difference category.
- **"Card" vs "Card (new)" visual** — initial instruction referenced both as competing options. Web-confirmed: the new Card visual replaced the classic Card as default in **November 2025 GA**; the legacy Card is now hidden in current PBI Desktop unless explicitly toggled on. Phil's Visualizations pane shows only one Card.

**Compounding factor**: "free vs paid" is a misleading frame. **Power BI Desktop is universally free for everyone** — there's no paid Desktop tier. The free/paid split is **Desktop vs Service** (Service is the paid cloud platform for sharing). When a user says "I'm on free Power BI", they almost certainly mean "Desktop only, no Service licence." Practical implication: skip all Service-only steps (scheduled refresh, publishing, workspaces, apps) and assume Desktop has the full feature surface modulo version drift.

**Discipline rule for any PBI walkthrough**: when an instruction references a specific UI element (button, visual, menu path, dialog field, ribbon section), either (a) ask the user to confirm what they see in their version *before* prescribing clicks, or (b) web-check the current state of that UI element rather than asserting from memory. Don't assume the UI Claude knows from training matches what Phil sees today.

**Captured durably in TEACHING_PREFERENCES.md** under Tooling — Claude should re-read at session start for any PBI work.

### 2026-05-18 — Mart-sourced measures break when sliced by item or store dims

Discovered mid-session in Phase 5 session 5.2 while building the Demand by Hierarchy page. Symptom: a clustered bar chart with `Y-axis = DIM_ITEM[cat_id]` and `X-axis = Sum of MART_EXECUTIVE_OVERVIEW[total_revenue_usd]` showed **the same value ($93.8M) for every category** (FOODS, HOUSEHOLD, HOBBIES).

**Root cause — design-predictable, not a bug.** `MART_EXECUTIVE_OVERVIEW` is a day-grain pre-aggregation with columns `sale_date, total_revenue_usd, total_units_sold, active_item_count, active_store_count`. By lean-marts design, it carries NO item or store identifiers — the fact's `item_id`/`store_id` columns were aggregated away at mart build time. Consequently, the mart has only ONE relationship in the PBI semantic model: `MART.sale_date → DIM_CALENDAR.calendar_date`. No relationship to `DIM_ITEM`, none to `DIM_STORE`. When a visual filters by `DIM_ITEM[cat_id]`, the filter has no path to the mart, so no filtering occurs — every slice gets the mart's grand total.

**Why this was a fresh discovery.** Session 5.1 built only the Executive Overview page using mart measures and `DIM_CALENDAR` slicers — the calendar relationship existed, so date-range slicing worked correctly and the bug was invisible. The hidden constraint was *"mart measures only work when sliced by calendar-related fields."* Page 1 happened to satisfy that constraint; pages 2-5 don't.

**The mart's own schema YAML comment anticipated the constraint** (`_marts__models.yml` line 5: "NO denormalised date attributes (Power BI joins dim_calendar for year/quarter/is_weekend/is_holiday slicing)") — but the comment framed it as a *date-attribute* design choice. It didn't surface the bigger consequence that **mart measures would fail to respond to ANY non-calendar dim filter** (item, store, state, category).

**Fix that was applied (session 5.2 reset, captured in POWERBI_PLAYBOOK.md).** All measures relocated from `MART_EXECUTIVE_OVERVIEW` to a new dedicated hidden `_Measures` table, with each measure rewritten to aggregate `FACT_DAILY_SALES` directly. The fact has many-to-one relationships to all 3 dims, so fact-based measures respond correctly to every slicer on every page. The mart stays loaded but is hidden from the PBI field list — kept as documentation of the lean-marts pattern in dbt without coupling the BI model to it.

**Discipline rule banked**: when a pre-aggregated table is joined to PBI alongside a fact, the table's relationship topology determines what dims its measures can be sliced by. If the pre-agg only relates to the calendar dim, its measures only work on calendar-only pages. For cross-dim slicing, measures MUST aggregate the fact. The mart is for the home page's compression story (1,081 rows powering an exec view instead of 32.9M); it's not the universal measure source.

**Carry-forward principle for Project #3**: any pre-aggregated table in a BI semantic model needs documented filtering boundaries — *"this agg can be sliced by [X, Y, Z]; for slicing by [A, B], use the underlying fact."* Goes in the model's YAML alongside the column descriptions, not just in the dbt comment.

### 2026-05-18 — Dedicated hidden `_Measures` table for measure organization

Locked in during Phase 5 session 5.2 reset, backed by SQLBI / Microsoft Learn. Pattern: create a single empty table called `_Measures` (leading underscore sorts it to the top of the field list), hide the placeholder column, and home all measures there. Measures don't need a data source — they're computed expressions; the "home table" is purely organizational.

**Why this beats homing measures on data tables.** (a) The field list separates *"things to drag onto visuals as dimensions"* (data tables) from *"things to drag onto visuals as values"* (measure table) — cleaner mental model. (b) Refactoring a measure to reference a different fact column is trivial when the measure has no data-table home — no "this measure is on `MART` but references `FACT`, is that wrong?" ambiguity. (c) Sorts alphabetically before all data tables thanks to the leading underscore — measures always at the top.

**How to create**: Modeling tab → New table → paste `_Measures = ROW("Placeholder", BLANK())`. Then in Fields pane right-click the placeholder column → Hide. Then for every new measure: right-click `_Measures` in Fields pane → New measure. PBI auto-homes the measure on `_Measures`.

**Carry-forward**: every new PBI project in any subsequent Project #N starts with `_Measures` created BEFORE the first measure is written. Don't accumulate measures on data tables and refactor later — costly.

### 2026-05-18 — Dual storage mode on dims joined to a DirectQuery fact

Decision locked during Phase 5 session 5.2 reset after audit + SQLBI / Marco Russo research. The setup is: `FACT_DAILY_SALES` in DirectQuery (forced by 32.9M-row size hitting GitHub's 100 MB push limit in pure-Import mode), all three dims previously in pure Import.

**The problem with Import dims + DQ fact.** Per SQLBI: a relationship between an Import dim and a DirectQuery fact is a **limited (weak) relationship**. Properties of limited relationships:

1. **Cannot use `RELATED`** to fetch a column across them.
2. **Skip table expansion** — internal optimizations that propagate filter context through chained relationships don't apply.
3. **INNER JOIN semantics** — drops rows from EITHER side that have no match, even when the other side semantically should be included.
4. **High-cardinality join keys are slow** — limited-relationship joins are evaluated row-by-row above ~100-200 unique values.

**Dual mode fixes all four.** Setting dims to Dual lets PBI's engine treat the dim as Import for in-memory queries AND as DirectQuery when joining to the live DQ fact at the Snowflake side. Relationships become **regular** at query time. Free in Desktop, zero downside, strictly better for this topology.

**How to set**: Model view → right-click table header → Properties → Storage mode → Dual. PBI prompts that the change is irreversible (Dual → Import or DQ requires recreating the table) → confirm. Three dims × 1 click each.

**Carry-forward**: any time a star schema spans storage modes (Import + DirectQuery), the Import dims should be Dual, not pure Import. Pure Import dims joined to DQ facts is an anti-pattern.

### 2026-05-18 — Backfill anti-pattern: full-chain vs `--task-regex`

Lesson from mid-session 5.2 — Claude initially proposed running the full Airflow extract → verify → dbt models → verify_dbt chain 68 times for a historical date backfill. That's the *canonical DAG* but the wrong tool for *historical hole-filling*. Sequential full-chain × 68 dates × 5:31 per run = ~6 hours unattended. Parallel with `--max-active-runs 4` halves it but still ~1.5h.

**The 25-min alternative**: `airflow dags backfill ... --task-regex extract_one_day -i`. Restricts the backfill to only the named task per DagRun; downstream tasks (verify, dbt, verify_dbt) are skipped. Each run is then ~20-30s (just the Azure SQL → Snowflake extract, no dbt rebuild, no test suite). 68 × 25s = ~25 min. Then one `dbt build --full-refresh` at the end (~18s + tests) rebuilds the whole warehouse from the fuller RAW in one shot.

**Why the wasted work**: full-chain × 68 means the dbt incremental MERGE fires 68 times, each time processing one date and re-running 78 tests. The tests are checking nothing that hasn't been checked, and the MERGEs are doing what one full-refresh would do in 22s. ~5.5 hours of pure waste.

**Add `--reset-dagruns`** if any DagRun records already exist for the target logical_date range (e.g. from a half-completed earlier attempt) — wipes them clean before the new backfill creates fresh ones. No double-ups.

**Discipline rule banked**: when proposing a multi-run Airflow operation, lead with the shortest professional approach. Surface the duration estimate explicitly *before* any command runs. If duration > 30 min, offer 2-3 explicit options (sequential / parallel / task-restricted) with their respective time costs before committing. Default = the fastest one that doesn't compromise data integrity.

### 2026-05-18 — Research-backed playbook as a mid-phase reset tool

Meta-lesson from Phase 5 session 5.2 mid-session reset. When a project's PBI build hit a measure-architecture bug 2 hours into the session, the right move was NOT to keep iterating step-by-step in chat. It was to STOP, spawn parallel research agents (one auditing the project's current state from docs + dbt files, one web-researching Microsoft Learn / SQLBI / RADACAD / Chris Webb for the architectural questions), synthesize into a single durable doc (`POWERBI_PLAYBOOK.md`), and update the live state docs (PROJECT_CONTEXT.md, TEACHING_PREFERENCES.md, this file).

**Why this is durable** beyond Phase 5: the playbook locks the architectural decisions (storage modes, measure home, mart fate, measure family source) with web-verified sources, so subsequent sessions can be **executed** rather than **re-litigated**. If a later step proposes something that contradicts the playbook, that's a flag to push back rather than proceed.

**Trigger condition for the pattern**: any time the project hits a "this design choice has cascading consequences across multiple future sessions, and we just discovered the consequence is wrong" moment. Don't power through. Reset, research, document, then resume.

**Carry-forward for Project #3**: at the start of any BI / dashboard / semantic-model phase, draft the equivalent playbook *before* building. The session-5.1 mistake was building Executive Overview before locking the measure architecture — the bug surfaced only when page 2 introduced cross-dim slicing requirements that page 1 didn't have.

### 2026-05-18 — Airflow extract anomaly + ground-truth-via-direct-execution diagnostic

Hit at session 5.2 mid-session during the 68-date backfill verification. Symptom: Airflow's `airflow dags backfill m5_daily_extract --start-date 2014-01-07 --end-date 2014-03-15 --task-regex extract_one_day -i --reset-dagruns` reported **67 of 67 succeeded** — but parity check showed only **66 new dates landed** in Snowflake RAW. One date (`ds=2014-01-06` = `d_1074`) was silently skipped despite the Airflow task instance state showing `success`.

**Diagnostic process — three steps, ground-truth-first**:

1. **Confirm Azure SQL has the row.** Wrote `scripts/check_azure_sql_calendar_gap.py` re-using the production extract module's `connect_azure_sql()` helper (so .env semantics = guaranteed-same as the DAG's runtime). Queried `raw.calendar` for date='2014-01-06' AND d='d_1074' AND for the d_1072..d_1076 window. Result: **row exists**, all 5 surrounding d_values present, `raw.calendar` total = 1,969 rows (full M5 dataset).
2. **Run the extract script directly.** From PowerShell with the project's `.venv` active: `python scripts/extract_azure_to_snowflake.py --run-date 2014-01-06`. Result: **clean load in 2 minutes** — 1 calendar row + 26,049 sell_prices rows (whole `wm_yr_wk=11350` week) + 30,490 sales_train rows, parity verifications all PASS.
3. **Conclusion**: Azure SQL is fine, the script is fine, the bug is somewhere in Airflow's context resolution under `--reset-dagruns` + `--task-regex` mode. Root cause not definitively proven — suspected interaction between Cosmos-integrated DAG parsing and the backfill's `ds` resolution when DagRun records are being recreated. Documented as known anomaly.

**The durable pattern banked: ground-truth-via-direct-execution**. When orchestration says SUCCESS but the data layer says otherwise, **invoke the underlying script directly with the same arguments the orchestrator would have passed**, in an environment that mirrors the orchestrator's (same Python, same .env, same connection helpers). Two outcomes possible: (a) script also fails the same way → bug is in the script; (b) script succeeds → bug is in the orchestrator's context, environment, or invocation path. Either outcome is actionable. The diagnostic burns only the script's runtime (~2 min here) versus debugging Airflow's task isolation, which can chew hours.

**Why re-using the production module's connection helpers matters**: writing a fresh `pyodbc.connect()` in the diagnostic script would have introduced a confound — "does the diagnostic script see Azure SQL the same way Airflow's task does?" By importing `extract_azure_to_snowflake` and calling its `connect_azure_sql()` + `wake_azure_sql()`, the diagnostic uses the exact same connection path Airflow uses, so a clean answer from the diagnostic is decisive about the script-or-script-internals layer.

**Discipline rule for future anomalies**: when "orchestrator says success but downstream check says missing data", reach for ground-truth-via-direct-execution before debugging the orchestrator. The orchestrator has more moving parts; the script is the simpler unit to isolate.

**Carry-forward for Project #3**: when wiring any orchestrator (Airflow, Prefect, Dagster, Argo) around an existing ETL script, keep the script independently runnable with the same `--run-date`-style CLI surface the orchestrator uses. This isn't just "good code hygiene" — it's the diagnostic surface for problems exactly like this one.

### 2026-05-18 — `.pbix` file size forced composite-mode decision at git-push time

Caught at session 5.1 close. Initial decision was **full Import** for all 5 tables in the semantic model — dims (small), mart (small), and the **32.9M-row `FACT_DAILY_SALES`** (large but reasoned: "VertiPaq compresses 5–10× and Import unlocks the full DAX surface"). The .pbix saved fine locally, but **`git push` was rejected by GitHub with**:

```
remote: error: File powerbi/retail_demand_forecasting.pbix is 949.08 MB;
this exceeds GitHub's file size limit of 100.00 MB
```

VertiPaq genuinely compressed the row data — 32.9M rows × multiple columns into ~600 MB is decent compression — but **GitHub's 100 MB per-file hard limit** is a real constraint that doesn't care about column-store internals. The `.pbix` is a single binary blob from git's perspective.

**The pivot**: switch `FACT_DAILY_SALES` from **Import** to **DirectQuery**. Composite-mode: fact stays in Snowflake and queries live for fact-driven visuals; dims + mart remain in Import for instant home-page interactivity. **Result**: `.pbix` dropped from **949 MB to 264 KB** — a ~3,600× reduction. Push went through cleanly without Git LFS.

**Mechanics — the trap to avoid**: PBI Desktop **cannot switch a table from Import to DirectQuery via the Properties pane Storage mode dropdown**. The dropdown is greyed out by design (web-confirmed via Microsoft Learn). The valid switches are: DirectQuery → Import (irreversible), DirectQuery → Dual, Import → Dual. Import → DirectQuery requires **delete the table from the model + re-add via Get Data and choose DirectQuery at the load dialog**. Relationships are lost on delete and must be rebuilt afterward (3 fact→dim relationships in our case — quick).

**Reframe for interview talk-track**: this isn't a setback — it's the actual empirical DirectQuery-vs-Import evaluation playing out. The original session plan called for "Native Snowflake connector with DirectQuery vs Import evaluation; settle the pattern empirically per page." That's exactly what happened. The empirical answer for THIS dataset at THIS scale in a git-versioned portfolio repo is **composite mode**, and the story behind it ("I tried full Import first, hit GitHub's 100 MB ceiling, pivoted to composite") demonstrates real operational maturity. *"I empirically evaluated Import vs DirectQuery per table. Small dims + the pre-aggregated mart land in Import for instant interactivity. The 32.9M-row fact stays in Snowflake under DirectQuery — clicks pay sub-second latency rather than baking a near-GB binary into the repo."*

**Three carry-forward principles for Project #3**:

1. **Estimate output artefact size BEFORE the empirical evaluation**, not after. Back-of-envelope: 32.9M rows × ~10 columns × ~30 bytes/value (uncompressed) = ~10 GB raw → VertiPaq 5–10× compression → ~1–2 GB in .pbix → exceeds GitHub by 10×. Would have caught this without the failed push.
2. **GitHub's 100 MB per-file limit is the hard constraint** for any git-versioned binary deliverable — `.pbix`, `.twbx` (Tableau workbook), `.parquet` snapshots, ML model artefacts. Plan around it from session 1, not session N when the push fails.
3. **Composite mode is the senior-DE default for any analytics tool consuming both small and large warehouse surfaces.** Small + slow-changing → Import (fast slice/dice, full DAX). Large + slow-changing → DirectQuery (no client storage, latency on click). Large + fast-changing → DirectQuery (freshness). Mixed → composite. Make this an explicit per-table decision, not a project-wide one.

### 2026-05-20 — Manage Aggregations requires DirectQuery on the Detail Table — architecturally incompatible with all-Import models

Discovered mid-rebuild in Phase 5 session 5.4. The `POWERBI_PLAYBOOK.md` §1.4 prescribed wiring `AGG_SALES_DAILY` and `AGG_SALES_DAILY_ITEM_CAT` as user-defined aggregations to accelerate Sum-based measures over the 32.9M-row fact. When I opened Modeling → Manage Aggregations and tried to map `DATE_KEY` (GroupBy summarization) to a Detail Table, every option in the dropdown was unclickable. Spent ~30 min on what looked like a UI bug (clicks not registering, options visually greyed) before web-checking the actual Microsoft Learn doc on aggregations-advanced.

**The actual rule, missed by the original playbook:** the Detail Table for any user-defined aggregation must be in **DirectQuery storage mode**, not Import. From Microsoft Learn: *"The Detail Table must use DirectQuery storage mode, not Import."* The aggregation table itself can be Import (and usually should be, for VertiPaq compression), but the table it maps INTO has to be DirectQuery so PBI can rewrite queries between Import-cached-agg and DQ-direct-fact at runtime.

**Why this matters for an all-Import model.** The playbook §1.1 explicitly locked the model to all-Import (no Dual, no DirectQuery, no composite) to avoid the Import → Dual one-way restriction trap and the lean-marts measure cascade bug from session 5.2. That decision was correct for those problems, but it forecloses the UDA path entirely. The two architectural choices are mutually exclusive: you can have all-Import simplicity OR user-defined aggregations, not both.

**Resolution.** Deleted `AGG_SALES_DAILY` and `AGG_SALES_DAILY_ITEM_CAT` from the PBI semantic model. They're still in Snowflake + dbt as a portfolio narrative artefact — *"I built two pre-aggregated marts following the Kimball aggregate pattern"* — but they don't get wired into PBI. Net result: measures hit `FACT_DAILY_SALES` directly via VertiPaq Import. Empirically: sub-second for Sum-based measures on 32.9M rows, so no measurable performance loss to deliver.

**Forward principle**: any time a playbook locks in a storage-mode decision (Import only / DirectQuery only / Dual / composite), explicitly enumerate which downstream optimizations that decision rules OUT. UDA is one. RLS row-level filtering on DQ-only tables is another. Hybrid tables for fast-changing data is a third. The storage-mode decision isn't just a perf choice — it cascades through every advanced PBI feature.

**Interview talk track**: *"I went all-Import for the semantic model because the alternative — DirectQuery on the fact + Dual on the dims — has a documented one-way restriction in PBI Desktop where you can't downgrade Import to Dual without re-importing as DirectQuery first. The cost of that decision was losing access to user-defined aggregations, which require a DirectQuery detail table. I kept the pre-aggregated marts in dbt for the architectural story but didn't wire them into PBI — VertiPaq compression on the Import-mode fact made the perf gap negligible at our scale."*

**Carry-forward to Project #3 (Databricks)**: Power BI on Databricks has the same UDA requirement — agg tables in Import, detail in DirectQuery. Decide storage mode BEFORE building the agg layer so you don't ship dead aggs to PBI like this project did.

### 2026-05-20 — Power BI measure formula editor: Enter does NOT commit when editing an existing measure; click the green checkmark

Discovered after burning ~30 min in Phase 5 session 5.4 trying to fix the `Active Items` measure. Symptom: card on canvas kept showing `--` (BLANK) regardless of which formula was typed into the measure formula bar. Iterated through 4 different DAX formulations — original (used `MAX(DIM_CALENDAR[calendar_date])`), then fact-side (`MAX(FACT_DAILY_SALES[sale_date])`), then `CALCULATE(DISTINCTCOUNT, units_sold > 0)`, then dead-simple `DISTINCTCOUNT(FACT_DAILY_SALES[item_key])`. ALL returned BLANK. Other measures on the same fact worked fine (Total Revenue, Total Units Sold, Active Stores all rendered correctly).

**The actual bug.** I was instructing Phil to press Enter to commit each new formula. In PBI Desktop's measure formula editor, **Enter does NOT commit when you're editing an EXISTING measure** — it inserts a newline (DAX supports multi-line formulas). The displayed text in the formula bar updates with each new formulation, but the SAVED measure definition stays at the original. Every "new" formula was just sitting unsaved in the editor while the broken original kept executing in the background, returning BLANK.

**Why other measures were fine.** When you click "New measure" from the Modeling ribbon, the workflow is different — Enter DOES commit-and-exit the new-measure dialog. All 20 measures during the bulk-paste phase were created via that workflow, so Enter worked. The trap is specifically when you go back to EDIT an existing measure by clicking it in the Data pane — different formula bar mode, different commit semantics.

**The fix.** Click the green checkmark icon to the LEFT of the formula bar text explicitly. The X (red) and checkmark (green when there are unsaved changes, grey when committed) are next to the formula. Clicking the green checkmark commits the edit. Pressing Enter just adds a line break.

**Forward principle, locked into PROJECT_CONTEXT 5.5 opening directive**: whenever Claude prescribes a measure edit (not a new-measure create), the instruction must include "click the green checkmark to commit, not Enter."

**Diagnostic technique worth banking**: when a DAX measure returns BLANK and there's no obvious filter context reason, the FIRST check should be "is the formula actually saved?" Not "is the DAX correct?" The committed formula vs displayed formula divergence is invisible until you click away and click back — then the formula bar shows the saved version, not the typed-but-unsaved version. Carry-forward for Tableau too (Tableau has analogous edit-mode-vs-saved-mode confusion in calculated fields).

### 2026-05-20 — Power BI Optimize → Pause Visuals as silent root cause of "everything disappears on click"

The biggest time-sink of Phase 5 session 5.5. Symptom from session open: every interaction in PBI Desktop (clicking a slicer, dragging a measure into a card, switching pages) caused visuals to go blank. Clicking Home → Refresh forced them to render. Next interaction → blank again. Pattern was so consistent Phil flagged it explicitly ("I click on something, everything disappears. I have to do a refresh.") roughly an hour into the session.

**The actual cause.** Optimize ribbon → "Pause Visuals" was toggled ON. Pause Visuals is a PBI Desktop feature meant for performance work — when on, every visual query is queued but NOT executed until you Resume or Refresh. The visual stays in whatever render state it was in before the pause, then blanks when you change anything that invalidates it (new field, new filter, page switch), because the new query never runs. Refresh forces the queue to flush, visuals render. Next interaction → queued again → blank again.

**Why it took so long to find.** Three reasons compounded:
- The pattern looked like a model/data bug at first ("DIM_ITEM[cat_id] slicer is empty" — data view showed 3,049 rows with FOODS/HOBBIES/HOUSEHOLD populated, so it wasn't the data).
- A refresh during diagnostics surfaced an unrelated "A cyclic reference was encountered" error pointing at FACT_DAILY_SALES, which became the red herring. Spent ~30 min tracing M-code (clean), query dependencies (clean), calculated columns (none), measures (intact). The cycle turned out to be spurious — close+reopen of the .pbix cleared it (see separate entry below).
- The "To format your visual, refresh it or resume visual queries" message in the Format pane was the actual giveaway — it appeared late in the session when Phil clicked a card to format it. The word "resume" in that message is what unlocked it.

**The fix.** Optimize ribbon → click Pause Visuals to toggle OFF. Icon behavior is the opposite of what you'd expect: when visuals are LIVE, the button shows a Pause symbol (II) meaning "click to pause." When PAUSED, it shows a Play arrow (▶) meaning "click to resume." Confusing UI affordance.

**Discipline rule locked, added to TEACHING_PREFERENCES.** Whenever the user reports "things keep disappearing when I click" / "I need to refresh after every change" / "visuals look empty until I refresh" — FIRST diagnostic before anything else is Optimize → Pause Visuals. It's a 1-click check with the highest signal-to-noise of any PBI diagnostic. Cyclic ref errors, empty slicers, blank cards, "needs refresh to render" — all are downstream symptoms of paused queries.

**How it likely got turned on.** Pause Visuals is a single-click button on the Optimize ribbon, easy to hit accidentally. Once on, it stays on through saves and reopens. No global toast or banner indicates the paused state — the only persistent cue is the icon style in the Optimize tab (which you only see if you're on that tab).

**Carry-forward to any future PBI work**: the Optimize tab and its toggles (Pause visuals, Refresh visuals, Apply all slicers button) are part of PBI's standard diagnostic surface. Worth learning what each one does proactively so symptoms map quickly to causes. Carry-forward also to Tableau (Pause Auto Updates serves the same function, same trap potential).

### 2026-05-20 — Power BI cyclic reference errors can be spurious; close + reopen the .pbix before deep-diving

Mid-session in 5.5, a Refresh surfaced: *"5 queries are blocked by the following error: FACT_DAILY_SALES — A cyclic reference was encountered during evaluation."* The natural first reaction is to chase the cycle through the model — Power Query M-code, query dependency graph, calculated columns, calculated tables, measure dependencies, bidirectional relationships, etc.

**What was actually wrong.** Nothing. The M-code for FACT_DAILY_SALES was clean (Source → 3 Navigation steps → drop SALE_KEY). Query Dependencies graph showed all 6 queries pulling independently from the one Snowflake source with no cross-references. No calculated columns on FACT_DAILY_SALES. The error was spurious.

**The fix.** Save → close Power BI Desktop entirely (red X) → reopen the .pbix from File Explorer. The cyclic reference error did not return after the reopen. Slicers that had been silently failing started returning values normally (the underlying Pause Visuals issue was still there, but the cycle itself was gone).

**The supporting evidence** (from a contemporaneous web search): the [crossjoin.co.uk article on this error](https://blog.crossjoin.co.uk/2023/01/22/understanding-the-a-cyclic-reference-was-encountered-during-evaluation-error-in-power-query-in-power-bi-or-excel/) explicitly notes: *"Sometimes the cyclic reference error is raised without an actual cyclic reference existing, another refresh doesn't raise the error, and it's better to refresh twice before investigating."* So this is a documented PBI quirk, not a one-off glitch.

**Discipline rule.** When PBI surfaces *A cyclic reference was encountered during evaluation*, the first step is save + close + reopen, NOT trace the model. Only if the error persists after reopen should you investigate M-code → Query Dependencies → DAX calc columns / tables → measure deps → bidirectional relationship cycles. Going straight to the trace burned ~30 min in 5.5 before the reopen cleared everything.

**Carry-forward.** Many PBI Desktop "intermittent or one-time-only" errors clear on reopen because PBI caches internal model snapshots that can desync from the live model state. When the symptom doesn't match the data (data is clean, formula is correct, relationships look right, error is still there) — reopen first.

### 2026-05-20 — Power BI new Card visual (Nov 2025 GA) renders blank when bound to a measure that works in other visuals

Symptom: created a fresh Card visual on Executive Overview page, dragged `Total Revenue` into the Value field well — visual rendered as an empty rectangle with no number. Same measure on the same page in a Line chart rendered correctly with `$100.70M` value visible in the legend tooltip.

**Confirmed via web search**: the [(new) Card visual went GA with the Nov 2025 Power BI release](https://learn.microsoft.com/en-us/power-bi/visuals/power-bi-visualization-card) and has a documented blank-render bug in PBI Desktop. The [Fabric Community thread](https://community.fabric.microsoft.com/t5/Desktop/New-Card-Visual-Missing-After-Latest-Power-BI-Update/m-p/4861831) describes the same symptom and offers "restoring the defaults" via the Format pane as the documented fix.

**The fixes that actually worked tonight (after disabling Pause Visuals):**
- The card rendered immediately once Pause Visuals was turned off. The blank-card issue was a downstream consequence of paused queries, not the GA bug. So the "new Card visual GA bug" may not have been the root cause in this specific instance — but it IS a known PBI Desktop issue and worth banking.

**What's actually banked.** If a measure renders blank in a fresh Card visual but works elsewhere on the same page, and Pause Visuals is confirmed OFF, the workarounds (in order of preference): (a) Format pane → Reset to default; (b) Delete the card and recreate; (c) Switch to the Multi-row card visual, which is a different visual type that doesn't share the new Card's render path.

**Why this matters for portfolio narrative.** Tonight's confusion (blank card AND paused visuals AND spurious cyclic ref all happening at once) reinforces a senior-DE diagnostic principle: **isolate one variable at a time**. When three things look broken, fixing all three with one action (turn off Pause Visuals) tells you they were all symptoms, not three independent bugs. Locked into a teaching-preferences carry-forward.

### 2026-05-21 — Power BI calculated COLUMN vs MEASURE: same formula bar, different evaluation context

Discovered during Phase 5 session 5.6 while adding `is_snap_day` to `DIM_CALENDAR` for the Promotion & Price page. Phil clicked "New measure" instead of "New column" — the formula bar looked identical, but every column reference (`DIM_CALENDAR[SNAP_CA]`, `[SNAP_TX]`, `[SNAP_WI]`) lit up with red squigglies and the error tooltip read "Cannot find name SNAP_CA". Confirmed the columns existed on DIM_CALENDAR via the Data pane; re-typing using Intellisense didn't fix it; only switching from New measure to New column cleared the error.

**The real distinction:**

- **Calculated COLUMN** evaluates in **row context** — runs once per row of the host table. Bare column references like `DIM_CALENDAR[SNAP_CA]` resolve to "the value of SNAP_CA on THIS row." Cheap to read in DAX.
- **MEASURE** evaluates in **filter context** — runs once per cell of a visual, with no inherent row context. Bare column references don't make sense (there's no single row to evaluate against) so DAX requires an aggregator (SUM, AVERAGEX, etc.). The "Cannot find name" error is PBI's slightly misleading way of saying "this reference can't resolve without row context."

**Mental model — clipboard-vs-turnstile.** A calculated column is like a clipboard handed to each row as it walks past — the row context is its identity. A measure is like a turnstile counter at the gate — it sees the FLOW (filter context) of rows passing through but has no concept of "this row" without an aggregator wrapping it.

**Why the same formula bar exposes both:** Microsoft chose UI parsimony over discoverability. The exact same DAX syntax can mean two completely different things depending on whether you clicked New column or New measure five seconds ago. Discipline rule: ALWAYS double-check the ribbon button before pasting a formula.

**Carry-forward.** Any time PBI surfaces "Cannot find name [column]" on a reference Phil can verify exists in the Data pane, the FIRST diagnostic check is "did I click New measure or New column?" — not "is the column name wrong?", not "is there a typo?", not "is Intellisense broken?". Saved ~10 min of misdirected diagnostics this session; would have saved more if checked first.

### 2026-05-21 — Snowflake unquoted identifiers stored as UPPERCASE carry through to Power BI column names

Surfaced during Phase 5 session 5.6 when the `is_snap_day` calculated column formula was authored as `DIM_CALENDAR[snap_ca]` (lowercase, matching dbt model source-of-truth) and lit up with red squigglies in PBI. The actual columns visible in PBI's Data pane were `SNAP_CA`, `SNAP_TX`, `SNAP_WI` — all uppercase.

**The chain:** dbt models write columns in lowercase (`snap_ca`, `snap_tx`, `snap_wi`). Snowflake stores unquoted identifiers as UPPERCASE (documented behavior — applies to all CREATE TABLE / SELECT / column references that aren't double-quoted). When PBI imports via the Snowflake connector, it reads whatever Snowflake returns — uppercase. So lowercase dbt source code → uppercase Snowflake catalog → uppercase PBI column names. DAX is case-insensitive for column REFERENCES but the column NAMES still need to match what PBI catalogued.

**Practical implication for DAX authoring:** when writing DAX measures or calculated columns that reference columns in a Snowflake-imported semantic model, default to UPPERCASE column names — or use Intellisense, which always pulls the exact catalog name. Don't free-type the column name in lowercase even though it works in your dbt source code.

**Edge cases worth knowing:**

- Double-quoted Snowflake identifiers preserve case (`CREATE TABLE "MyTable"` stays "MyTable"). The dbt convention to use unquoted snake_case is what produces clean uppercase in the catalog.
- Identifiers with special characters (spaces, hyphens, leading digits) get auto-quoted by some tools and may retain original casing — another reason to stick to plain snake_case throughout the stack.
- BigQuery is case-SENSITIVE for column names by default — same dbt source produces case-preserving column names. The lesson here is Snowflake-specific.

**Carry-forward.** When DAX authoring against a Snowflake-imported model and a bare column reference doesn't resolve: check casing FIRST (UPPERCASE for unquoted Snowflake), table name SECOND, column existence in the Data pane THIRD. Cheapest checks first.

### 2026-05-21 — The `(Mart)` measure naming pattern: same metric, two source tables, two measures

Discovered during Phase 5 session 5.6 while building the Forecast vs Actual matrix. Playbook §3.5 specified the matrix as `Rows=cat_id, Columns=series_type, Values=Total Units, Total Revenue` — but the existing `Total Revenue` and `Total Units Sold` measures (from playbook §2.1) source from `FACT_DAILY_SALES`, which has no `series_type` column. Putting `series_type` in matrix Columns would have no filtering effect on FACT-sourced measures: both the "actual" and "forecast" columns would show the same $100.70M total because the column-level filter can't reach the source table.

**Fix:** added two NEW measures — `Total Units (Mart)` and `Total Revenue (Mart)` — that source from `MART_FORECAST_VS_ACTUAL` (the dbt mart that UNIONs actuals and forecasts with a `series_type` discriminator). The matrix now uses these mart-sourced measures, the column filter does its job, and we get a clean actual vs forecast split: FOODS shows 25.9M actual units / $59.7M revenue alongside 696K forecast units / $1.7M revenue.

**The naming convention.** Suffix the mart-sourced version with `(Mart)` rather than renaming the fact-sourced original. Reasons:

1. The fact-sourced version is the canonical company-wide measure — every page outside Forecast vs Actual uses it. Renaming it would force ripple changes.
2. The `(Mart)` suffix is a self-documenting signal that the measure has different source semantics. A future reader sees the suffix and knows to check the source table.
3. The two measures coexist on `_Measures` and sort alphabetically together — visible side-by-side in field lists, making the relationship obvious.

**When to reach for this pattern.** Any time you have two source tables that represent the same metric at different scopes — actuals vs forecast, current vs prior period at table level (not measure level), unified vs filtered subsets. Better than trying to consolidate into one measure with complex CALCULATE logic — explicit beats clever in DAX as much as it does in Python.

**Anti-pattern to avoid.** Don't reuse the same measure name on two different tables (PBI prevents this anyway — measure names are globally unique in the model). Don't use ambiguous suffixes like `(v2)` or `(new)`. The suffix should signal the SOURCE or SCOPE difference, not version.

**Carry-forward to Project #3.** When Data Vault 2.0 hubs/satellites + Gold information marts both expose the same metric (revenue, units, customer count), the same pattern applies: explicit suffix on the mart-sourced measure (`Revenue (Gold)` alongside `Revenue (Vault)`), let the field list show them side by side.

### 2026-05-21 — Power BI format pane section names vary by visual type (Bars / Columns / Markers / Slices)

Surfaced during Phase 5 session 5.7 polish pass when I (Claude) repeatedly told Phil to click "Format → Visual → **Bars** → Colors" for the Average Selling Price chart on Promotion & Price. The dropdown didn't exist because the chart was a **clustered column** (vertical bars), not a horizontal bar chart — and in the new Power BI Desktop format pane the section is called **Columns** for column charts, **Bars** for bar charts, **Markers** for scatter / bubble charts, and **Slices** for pie / donut charts. Each parent section contains the visual's color controls, but the parent's name follows the visual type, not a uniform "Colors" parent.

**The chain.** The "old" Power BI format pane had a flat-ish structure with "Data colors" as a near-universal subsection at the top level of the Visualizations format pane — same name across most visual types. The redesigned pane (rolled out 2023-2024 and now standard in 2026) groups formatting controls under visual-type-specific parent sections. Same control, different parent label. Made worse by the fact that conditional formatting (`fx` button) lives inside whichever parent section the colors are under — so the click path is different for each visual type.

**Practical impact during 5.7.** I gave Phil three wrong paths in a row before he insisted I deep-think and web-check the actual UI. Confirmed via Microsoft Learn:

- Bar chart (horizontal) → Format → Visual → **Bars** → Color → fx
- Column chart (vertical) → Format → Visual → **Columns** → Color → fx
- Scatter / bubble → Format → Visual → **Markers** → Apply settings to (per-series dropdown) → Color
- Donut / pie → Format → Visual → **Slices** → Colors → fx
- Line chart → Format → Visual → **Lines** → Colors

**Carry-forward discipline.** When giving Power BI format-pane click paths in 5.8 and beyond, web-check the visual type's parent section name FIRST if I can't see the Format pane directly in the user's screenshot. Don't assume a generic "Colors" parent. If a path doesn't click, ask the user what parent sections are visible in their pane rather than guessing again. Cost ~10 minutes mid-session before Phil pushed back; cheap to avoid in future by visual-type-checking upfront.

**Edge cases worth knowing:**

- The **Apply settings to** dropdown inside Markers / Bars / Columns is what gates per-series customization. If a user can't find per-category color controls, it's usually because they haven't switched the dropdown off "All" yet.
- Conditional formatting via `fx` is only enabled when "Apply settings to" = All. Per-series manual colors bypass the fx dialog entirely.
- The Power BI documentation on Microsoft Learn for the new Card visual, scatter chart, donut chart, etc. each describe their parent section names directly — the docs are the source of truth, not stale community blog posts that still show the old "Data colors" path.

### 2026-05-21 — Power BI new Card visual Reference labels field well is variant-dependent (basic-license PBI Desktop is missing it)

Surfaced during Phase 5 session 5.7 polish pass when trying to add a YoY % indicator to the Total Revenue card on Executive Overview. Standard pattern for the new Card visual (Nov 2025 GA) is to drag the YoY measure into the **Reference labels** field well — gives a small secondary value below the main number, color-coded against the change. The screenshot of Phil's Build visual pane on the card showed only: **Value, Categories, Tooltips, Drill through**. No Reference labels field well.

**The chain.** The new Card visual's Reference labels feature shipped as part of the November 2025 GA release, but the field well's exposure in the Build pane appears to be license-tier-gated or variant-specific. Phil is running stock-standard Power BI Desktop with no Pro / PPU / Premium license. Microsoft's documentation describes Reference labels as a core feature of the new Card visual; community threads from late 2025 / early 2026 show two distinct Build-pane variants — one with Reference labels exposed, one without — with no clear pattern as to which license tier or feature flag drives the difference. The Reference labels field well is sometimes present in identical-version PBI Desktop installs on different machines.

**Practical impact during 5.7.** I'd planned 5 time-intelligence visuals on Exec Overview (YoY % pill, YTD line overlay, 30-day MA, etc.). The YoY % visualization was meant to use Reference labels on the Total Revenue card. With the field well unavailable, the only paths forward were:

1. Build a separate Multi-row card next to the Total Revenue card showing the YoY measure — added visual clutter, abandoned.
2. Build a custom DAX measure that returns the YoY % as a formatted text string, then put it in the Tooltip — usable but the YoY signal is hidden behind hover, doesn't read at-a-glance.
3. Skip the YoY % visualization entirely — chosen path. YoY measure retained on `_Measures` for tooltip use; the at-a-glance YoY indicator deferred.

**Feature-detect discipline.** Before recommending any new-visual field-well pattern (Reference labels, Small multiples, dynamic format strings, etc.), ask for a screenshot of the user's Build visual pane and confirm the field well exists. Don't assume the feature is present just because it's in the Microsoft documentation. New Power BI visuals roll out features incrementally across license tiers and feature flags; the GA announcement does not guarantee universal exposure.

**Carry-forward to Project #3.** Same discipline applies to any incrementally-released BI tool feature — Tableau, Looker, Mode, etc. Doc-described capabilities and user-visible capabilities are not always the same set. Screenshot-first feature-detect saves the time wasted recommending a path the user can't take.

### 2026-05-22 — Power BI Desktop format pane control locations vary heavily by variant — pin exact paths for common controls

Surfaced repeatedly during Phase 5 session 5.8 polish pass. The new Power BI Desktop format pane has been reorganised through 2024-2026 and controls don't always live where Microsoft Learn or community blogs say they do. Worse, in this user's stock free Desktop variant, some controls were in non-obvious sub-sections that required multiple research detours to find. Pinning the actual locations as confirmed in this user's variant (May 2026 stock free Desktop):

**Matrix controls:**

- **Row padding** → Format → Visual → **Grid** → **Options** sub-card → Row padding (NOT in Row headers / NOT in Values — both have Font/Text/alignment only)
- **Global font size** for all matrix text → Format → Visual → **Grid** → **Options** → Global font size (one control bumps all matrix text proportionally; cleaner than per-section font edits)
- **Auto-size column width / Grow to fit** → Format → Visual → **Layout** → **Column width** → Auto-size behavior dropdown = "Grow to fit"; companion toggle: **Custom widths** must be OFF for Grow to fit to actually distribute evenly (custom widths from prior manual drags override Grow to fit per-column)
- **Conditional formatting (background gradient, blank value handling)** → Format → Visual → **Cell elements** → "Apply settings to" dropdown (pick the target measure) → Background color toggle ON → click **fx** for the gradient dialog. Inside the dialog: "Apply to" = Values only excludes the Total column/row from the gradient; "How should we format empty values?" = Don't format (or Specific color → No fill) kills the gradient on truly-empty cells. The other CF access route via Build pane → Values well → ▾ on the measure → Conditional formatting works equivalently but only when the visual is selected.

**Format pane section names vary by visual type** (already locked 2026-05-21):

- Bar chart (horizontal) → Bars section
- Column chart (vertical) → Columns section
- Scatter / bubble → Markers section
- Donut / pie → Slices section
- Line chart → Lines section

**New Card visual field wells are Value / Categories / Tooltips / Drill through — NEVER "Fields well".** Banking this explicitly because saying "Fields well" wasted time across multiple turns. The classic Card visual had a "Fields" well; the new Card visual (Nov 2025 GA, default in current builds) uses "Value" as the primary field well name. Reference labels field well is variant-dependent (locked 2026-05-21).

**Carry-forward discipline:** when an instruction references any specific format pane section, sub-card, or field well name, web-check the EXACT location in the user's variant by asking for a screenshot of the relevant pane FIRST. Don't prescribe from memory of where it "should be" based on docs. Variant differences are real and prescribing-and-correcting wastes the user's time more than asking-and-confirming up front.

### 2026-05-22 — Power BI build order: pick theme + test drill-through EARLY with 1-2 visuals, NOT at polish-pass time

Two related carry-forward discipline rules surfaced after session 5.8's painful drill-through and theme-cohesion experiences. The user specifically asked these be banked for Project #3.

**Rule 1 — apply theme after 1-2 visuals exist, not after the report is built.** Power BI themes propagate font sizes, colors, default visual styling, and spacing across every visual on every page when applied. Building all 22 visuals across 5 pages with default formatting and then applying the theme at the polish-pass stage means every previously-formatted visual gets some properties overwritten or reorganized — net effect is rework on the visual formatting that was already invested. Build 1-2 visuals first, apply the theme, verify it looks how the user wants, then continue building. Theme-first means subsequent polish layers on top of the theme cleanly.

**Rule 2 — wire and TEST drill-through with 1-2 source visuals + a minimal destination page, BEFORE investing in source-visual formatting.** Power BI drill-through has known fragility around right-click trigger detection (community threads cite various causes: lineage mismatch, hidden destination page, blocked dim table, Page type setting, variant differences in the Page information section). When the right-click trigger fails to fire despite spec-correct wiring, the most commonly-cited community fix is to delete and re-add the source visual. If the source visual has already been polished with category-keyed colors, title renames, format-pane work, etc., that polish is lost. Testing drill-through EARLY with a minimal source visual (just the field, no formatting) means a failed trigger only costs 30 seconds of re-add. Testing drill-through LATE means losing significant polish work.

**Carry-forward to Project #3:** add "apply theme after first 1-2 visuals" and "wire + test drill-through after first 1-2 source visuals" as two locked steps in the Power BI build order, before the full visual build. Project #3's Power BI playbook should bake these in at the page-build phase, not the polish phase.

### 2026-05-22 — Power BI Desktop drill-through right-click trigger silently failing despite spec-correct wiring (unresolved)

Surfaced during Phase 5 session 5.8. Drill-through destination page "Item Detail" was created and hidden, drill-through field well wired with DIM_ITEM[ITEM_ID], "Allow drill through when = Used as category", Keep all filters Off, Cross-report Off. Source visual on Demand by Hierarchy was a Table with DIM_ITEM[ITEM_ID] in Columns well (lineage confirmed via tooltip showing 'DIM_ITEM'[ITEM_ID]). File saved + full close+reopen attempted.

**Symptom.** Right-click on an ITEM_ID value in the source table showed the standard context menu (Copy / Show as table / Include / Exclude / Group / Summarize / New visual calculation / Set up a verified answer / Customize total calculation) — but NO **Drill through** option.

**Diagnostics attempted (all checked, none resolved the issue):**

- Page hidden vs unhidden — same result
- Right-click on ITEM_ID text cell directly vs on revenue cell vs on total row — same result
- Allow drill through when = Used as category (verified, didn't change)
- Keep all filters Off (verified)
- Cross-report Off (verified)
- Source visual ITEM_ID lineage = DIM_ITEM[ITEM_ID] (verified via tooltip)
- Save → close PBI Desktop → reopen (verified, didn't resolve)
- Page type dropdown in Page information — NOT EXPOSED in this user's variant (only Set as landing page / Allow use as tooltip / Allow Q&A — no "Drillthrough" page type toggle; community thread on this control as the #1 cause didn't apply to this variant)

**Resolution:** drill-through was PULLED from session 5.8 scope. Item Detail destination page deleted. The cost-benefit on continuing to chase a variant-specific UI issue versus moving on to the remaining 5.8 items was not worth it for a portfolio piece focused on the data engineering story. PBI's automatic cross-filtering (left-click on a value in one visual filters all other visuals on the same page) gives most of the interactive value already, without the drill-through wiring complexity.

**Carry-forward discipline:**

- When drill-through right-click trigger fails despite spec-correct wiring in a free stock Desktop variant, the community-cited "Page type = Drillthrough" fix may not apply (the toggle may not exist in all variants — Page information section only exposed Allow use as tooltip / Allow Q&A / Set as landing page in this user's case). Investigation beyond this point requires screen-sharing for variant-specific diagnosis.
- Recommend treating drill-through as a "nice-to-have polish item" with a hard time-cap on debugging (e.g., 30 minutes). If not firing after spec-correct wiring + close+reopen, pull from scope rather than burning hours.
- See related carry-forward rule above: test drill-through EARLY with minimal visuals, before investing in source-visual formatting.

### 2026-05-22 — Power BI cyclic reference revisit: not always spurious cache — can also be real Power Query M-code self-reference

Update / refinement to the 2026-05-20 (session 5.5) LEARNING that locked cyclic reference errors as "almost always spurious cache desync, save+close+reopen fixes it."

5.8 surfaced a second occurrence of the same `"A cyclic reference was encountered during evaluation"` error pattern, this time on DIM_ITEM and DIM_STORE after a Power Query Replace Values transformation was applied to MART_FORECAST_VS_ACTUAL.SERIES_TYPE (renaming categorical values "actual" → "Actual", "forecast" → "Forecast"). The save+close+reopen path from 5.5 didn't always clear it on first attempt.

**Two distinct causes for the same error message:**

1. **Spurious cache desync** (5.5 pattern) — save+close+reopen clears instantly. Common after refresh / model changes / measure edits.
2. **Real Power Query M-code self-reference** (5.8 pattern) — a Replace Values step (or any Table.* transformation) references the query name itself instead of `#"PreviousStepName"` in the first argument. Self-reference creates a real evaluation loop that close+reopen cannot fix. Pattern: `= Table.ReplaceValue(QueryName, ...)` instead of `= Table.ReplaceValue(#"PreviousStep", ...)`. The Replace Values UI sometimes auto-generates the self-reference form depending on user actions.

**Updated diagnostic order for "cyclic reference" errors:**

1. Save + close PBI Desktop + reopen — clears spurious cache cases (5.5 pattern, fast)
2. If error persists after reopen → open Power Query Editor → click each affected table in the left panel → for each Applied Step, look at the formula bar M code → first argument must be `#"PreviousStepName"` (a step name with `#""` wrapper), NOT the query name directly
3. If a step references the query name, edit the formula bar to reference the prior step name → Close & Apply
4. If still failing, more involved tracing (Query Dependencies graph, calculated columns, relationship audit) per crossjoin.co.uk / community.fabric.microsoft.com diagnostic patterns

Source: [community.fabric.microsoft.com — Cyclic ref Replace Values self-reference pattern](https://community.fabric.microsoft.com/t5/Desktop/quot-A-cyclic-reference-was-encountered-during-evaluation-quot/m-p/3425258)

**Carry-forward:** treat cyclic ref as a two-cause symptom, not a single one. Cheapest diagnostic first (close+reopen), then M-code inspection if needed.

### 2026-05-22 — Power Query Replace Values is the ONLY stock-Desktop path for renaming categorical column values

Surfaced during Phase 5 session 5.8. User had a matrix with column headers driven by a categorical column SERIES_TYPE containing values "actual" and "forecast" (lowercase per dbt convention propagated through Snowflake unquoted-identifier UPPERCASE values). Wanted those headers to display as "Actual" / "Forecast" (properly cased).

**Paths investigated:**

- **In-visual "Rename for this visual"** → works for measure pills in field wells (e.g., renaming a Total Revenue (Mart) measure header to "Revenue"), but does NOT work for category values that drive column headers via a Columns field well. Confirmed via community.fabric.microsoft.com thread: "currently for matrix visual, there is no support for dynamically changing column names, and it is not possible for the headers to be dynamic."
- **Data View / Table View in-place edit** → not supported, PBI Desktop Table View is read-only for cell values
- **DAX calculated column with SWITCH** → works (creates a new column returning "Actual" / "Forecast" based on SERIES_TYPE value), bind matrix Columns well to the new column. Adds a column to the model.
- **Data Groups** → works, but creates a "(groups)" version of the field with similar overhead as a calc column
- **Power Query Replace Values** → modifies the existing column's data at load time. No new column created. Cleanest, community-recommended path. Requires opening Power Query Editor (Home → Transform data) and re-applying via Close & Apply (model refresh wait).
- **Update at dbt source layer** → best long-term but biggest commit; rebuild required

**Chosen path in 5.8:** Power Query Replace Values. Worked correctly; matrix redrew with "Actual" / "Forecast" / "Total" properly cased.

**Carry-forward discipline:**

- For categorical value renames in PBI semantic models, Power Query Replace Values is the cleanest stock-Desktop path. Confirmed by Fabric Community: there is no in-visual rename mechanism for category values driving column headers.
- For Project #3's Data Vault scenarios, decide at dbt source layer whether values like "actual" / "forecast" / "active" / "inactive" should be properly-cased at source (Snowflake/Databricks string functions) OR at the BI layer via Power Query. Source-side fix is more durable; BI-side fix is faster iteration.

Sources:
- [community.fabric.microsoft.com — Rename column header in matrix when column represents column value](https://community.fabric.microsoft.com/t5/Desktop/rename-a-column-header-in-matrix-visual-when-column-represents/m-p/3077461)

### 2026-05-22 — PBI transformation layer hierarchy: do data cleanup as close to source as possible (dbt → Power Query → DAX → visual)

Surfaced as a meta-pattern from 5.8 retrospective. Across the session we made multiple data-shaping decisions and didn't always pick the right layer. Locking the hierarchy explicitly.

**The layered transformation hierarchy (do cleanup at the LOWEST layer possible):**

1. **Source layer (dbt models / SQL transforms in Snowflake/Databricks/Postgres)** — best for stable, reusable transforms consumed by multiple downstream systems (PBI + ad-hoc SQL + other BI tools). Examples: properly-cased categorical values, derived calendar attributes, conformed dimensions, business-rule-driven boolean flags. If "actual"/"forecast" should be properly-cased everywhere, fix in dbt — then PBI inherits the clean values for free.
2. **Power Query (M) at PBI load time** — second best, for PBI-specific transforms that should happen automatically on every refresh. Examples: Replace Values for casing fixes; Remove Columns for fields PBI doesn't need; Change Type for numeric/date conversions; Merge/Append for combined sources; Conditional Column for derived text. Persists across refreshes. No model-side overhead. Slower to build but faster runtime than calc columns.
3. **DAX calculated columns** — only when row context is needed AND Power Query can't handle the same transform (rare — PQ Conditional Column covers most cases). Calc columns recalculate on every model refresh and consume VertiPaq memory. Examples where calc column IS the right tool: time intelligence patterns referencing related measures, complex DAX patterns that can't be expressed in M.
4. **DAX measures** — for dynamic aggregations evaluated at query time, not for data cleanup. Measures should compute, not rename.
5. **Visual-level (Filter pane, Rename for this visual, custom format strings)** — last resort, only for per-visual customization that doesn't generalize. "Rename for this visual" is a presentation-layer fix, not a data fix.

**Concrete examples from 5.8 — what we did vs what would be better:**

- **Did right:** Power Query Replace Values for SERIES_TYPE column on MART_FORECAST_VS_ACTUAL (actual → Actual, forecast → Forecast). Persists across refreshes, no calc column overhead, source data layer (dbt) untouched. Even better would be fixing at dbt source, but PQ is the right second choice.
- **Could have done better:** Day Type and SNAP Day Type calc columns on DIM_CALENDAR returning "Weekend"/"Weekday" and "SNAP Day"/"Non-SNAP Day" text. These could equally have been Power Query Conditional Columns on DIM_CALENDAR's M query — same result, slightly lighter VertiPaq footprint, transform lives in the load-time query graph rather than the model. For project consistency though, having all DIM_CALENDAR derived attrs as calc columns is also defensible. Trade-off: PQ keeps the M code graph cleaner; calc columns are easier to edit in PBI without leaving the model view.
- **Best path for Project #3:** push these transforms upstream into dbt where possible (the dim_calendar model can include `day_type` and `snap_day_type` columns natively). PBI then imports clean, semantically-named columns and skips both the PQ step AND the calc column step. Source-side transformations are also reusable for non-PBI consumers (ad-hoc SQL, other BI tools, ML pipelines).

**Other Power Query disciplines worth practicing in Project #3:**

- **Remove unused columns at load time.** Power Query → right-click column header → Remove. Reduces .pbix size, improves refresh speed, keeps the Data pane uncluttered. Doing this at PBI side instead of dbt side is fine when the dbt model is consumed by multiple downstream tools that need different column subsets.
- **Change column types explicitly.** Power Query auto-detects types but the detection isn't always right (e.g., a numeric ID column might be inferred as decimal when it should be whole number; a date string might come in as text). Explicit Change Type steps make the model more deterministic.
- **Rename columns for human readability at load.** snake_case from dbt → human-readable headers in Power Query (e.g., `total_revenue_usd` → `Revenue`). Centralizes the renaming so every visual using that column inherits the friendly name. Beats Rename for this visual which only fixes one visual.
- **Filter at load time, not visual time.** If certain rows should never appear in PBI (e.g., test data, soft-deleted records), filter them out in Power Query — not via Filter pane on every visual.

**Carry-forward discipline for Project #3:**

- Default: cleanup transforms in dbt at source. If not possible, Power Query at load time. DAX only when M can't express it. Visual-level only for per-visual presentation tweaks.
- Project #3's POWERBI_PLAYBOOK should include a "Power Query checklist at load time" section: rename columns to human-friendly names; remove unused columns; explicit type conversions; replace casing/text inconsistencies; document any non-obvious Power Query steps in M comments.
- Make this a mandatory step in the PBI build order — happens AFTER Get Data, BEFORE building any visuals. Easier to maintain clean transforms when the model loads correctly from day 1 vs retrofitting later.

### 2026-05-22 — DAX Studio External Tools registration requires "Install for all users" — per-user install doesn't expose the ribbon tab

Surfaced during Phase 5 session 5.8 when setting up VertiPaq Analyzer for the model-size talk-track artifact. Installed DAX Studio (latest), chose "Install for me only" to avoid admin prompt, ticked "Register as External Tool for Power BI" during install. After reopening PBI Desktop with the .pbix loaded, the **External Tools ribbon tab did not appear**.

**Root cause** (per community.fabric.microsoft.com): the per-user install path places `daxstudio.pbitool.json` in `%LOCALAPPDATA%\DAX Studio\` instead of the all-users path `C:\Program Files (x86)\Common Files\Microsoft Shared\Power BI Desktop\External Tools\` which is where PBI Desktop scans for external tool registrations. Per-user install completes successfully but the registration file is in the wrong location for PBI Desktop's discovery.

**Two verified fixes:**

1. Reinstall DAX Studio choosing **"Install for all users"** (requires admin / UAC prompt). Registration file lands in the correct scanned path. External Tools tab appears.
2. Manually copy `daxstudio.pbitool.json` from `%LOCALAPPDATA%\DAX Studio\` into the all-users Common Files path above (needs admin to write to Program Files).

**Workaround if neither admin path is available:**

Launch DAX Studio standalone from Start Menu → in the Connect dialog → select the **Power BI / SSDT Model** radio button → it detects running PBI Desktop instances dynamically. Loses the convenience of one-click launch from External Tools ribbon but functionally equivalent.

Source: [community.fabric.microsoft.com — External Tools Ribbon Missing](https://community.fabric.microsoft.com/t5/Desktop/External-Tools-Ribbon-Missing/td-p/3196052)

**Carry-forward:** for Project #3, when installing external tools (Tabular Editor, DAX Studio, Bravo for Power BI, ALM Toolkit), default to "Install for all users" to ensure External Tools ribbon registration. Note this in Project #3's tooling setup checklist.

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

### 2026-05-13 — `Connection Timeout=` in ODBC string silently ignored

**Symptom:** First run of `extract_azure_to_snowflake.py` against a cold (auto-paused) Azure SQL Free Serverless DB. Failed with `pyodbc.OperationalError: [08001] Login timeout expired (0); Invalid connection string attribute (0)` after **16 seconds** — despite our connection string containing `Connection Timeout=90;`.

**Diagnosis:** Our 90-second timeout was never being applied. The 16s figure is suspiciously close to ODBC Driver 17's *default* login timeout (~15s). The `Invalid connection string attribute (0)` clause in the error was the giveaway — the keyword in the connection string was being silently rejected by this driver/pyodbc combo. Phase 1's `load_m5_to_azure_sql.py` had the *exact same* pattern and "worked," but only because the DB happened to wake in time before the unconfigured default fired.

**Fix:** Move the timeout out of the ODBC string and into pyodbc's actual login-timeout parameter via SQLAlchemy `connect_args`:

```python
engine = create_engine(
    f"mssql+pyodbc:///?odbc_connect={quoted}",
    connect_args={"timeout": 90},   # pyodbc honors this reliably
)
```

`connect_args["timeout"]` is passed to `pyodbc.connect(timeout=…)`, which is the canonical Microsoft/pyodbc-documented place to set login timeout. The connection-string form is a hint that some drivers honor and some don't.

**What this taught me:**

- **A keyword that "looks right" in a connection string isn't necessarily honored.** Default-falling-back-silently is the worst class of failure mode because the symptom (timeout) doesn't point at the cause (configuration ignored). Look for the secondary clue — here, `Invalid connection string attribute (0)`.
- **Phase 1's `load_m5_to_azure_sql.py` has the same latent flaw.** It hasn't bitten because that script runs after a smoke test that already woke the DB. Worth a small side-quest fix when convenient — same one-liner: switch to `connect_args={"timeout": 90}`. Until then, the script is fragile on cold-start runs.
- **Carry-forward to Project #3:** when adding timeouts/retries to any database connection, verify the actual underlying library's recognized parameter shape (kwarg vs connection string), not just whatever shape worked in a tutorial. ODBC drivers especially are inconsistent across versions and providers about keyword recognition.

### 2026-05-14 — Azure SQL Free Serverless error 40613 (database paused, fast-fail on cold connect)

**Symptom:** First connection attempt of the 3-year backfill (overnight after session 2). Failed *instantly* with `pyodbc.Error: ('HY000', "... Database 'sqldb-m5-source' on server '...' is not currently available. Please retry the connection later. (40613)")`. Not a timeout — the error returned in well under a second.

**Diagnosis:** Auto-pause had fired sometime overnight since session 2 finished. This is a *different* failure class from session 2's `Connection Timeout` issue. pyodbc isn't timing out — Azure SQL is *explicitly* returning **error code 40613** to say "I heard you, I'm waking, retry later." The 90-second `connect_args["timeout"]` fix from session 2 doesn't help here because nothing is waiting to time out.

**Fix:** `Start-Sleep -Seconds 45` in PowerShell, then re-run the exact same command. Second attempt connected cleanly — the wake-up that the first attempt triggered had completed by then.

**What this taught me:**

- There are at least **two distinct cold-start failure modes** on Azure SQL Free Serverless:
  1. **Silent timeout class** (session 2's bug, now fixed). pyodbc gives up after its default ~15s while the DB is still booting.
  2. **Explicit 40613 fast-fail class** (today). Azure SQL replies immediately with "not available, retry later" before the connection even gets to the login stage.
- The session-2 fix solves (1) but not (2). They need different handling.
- **Production-ready code should wrap `engine.connect()` in a retry loop** that catches error 40613 specifically (and ideally the related 40197 "service is busy" code too), with 2-3 attempts at 30-60s spacing. Logged as a small follow-up improvement to `scripts/extract_azure_to_snowflake.py` — not blocking Phase 2 closeout but worth fixing before Airflow wraps the script in Phase 3 (otherwise the first scheduled run after overnight idle will fail until the second retry).
- **Diagnostic habit:** when a "database connection failed" error appears, read past the generic part to the *specific error code in parentheses*. The number is the signal: `08001` = network/login layer; `40613` = paused-and-waking; `40197` = transient busy. Each has a different fix.
- Carry-forward to Project #3.

### 2026-05-12 / 2026-05-13 — Verified the shape, not the product

**Symptom:** Overnight bulk load script ran cleanly for 11 hours, then exited with `ValueError: Row count mismatch for raw.sales_train: got 59,181,090, expected 59,180,090` at the very end. Looked like a load failure when first seen in the morning terminal.

**Diagnosis:** Data was correct. The script's `EXPECTED_ROWS["sales_train"]` constant had an off-by-1000 arithmetic error: `30,490 series × 1,941 day columns = 59,181,090`, not the 59,180,090 written in the constant. The verification function correctly compared `actual != expected` and raised — exactly as designed. The _expected value itself_ was wrong.

**Fix:** Updated `EXPECTED_ROWS["sales_train"]` to 59,181,090 in `scripts/load_m5_to_azure_sql.py`. Confirmed actual data via manual `SELECT COUNT_BIG(*)` in Azure Query editor (matched 59,181,090). No re-load needed.

**What this taught me:** Verifying the _shape_ of an arithmetic operation ("30,490 rows × 1,941 day columns") is not the same as verifying the _product_. The dimensions were checked correctly (CSV inspection confirmed 30,490 rows and 1,941 day columns), but the multiplication itself was wrong by 1,000 and never independently recomputed — writing "30,490 × 1,941" makes the answer feel obvious enough not to double-check.

**Going forward:**

- When a magic number guards verification, **compute it via two independent routes** (e.g., Python arithmetic AND a `SELECT 30490 * 1941` directly in SQL).
- Better still — **derive expected values from runtime measurements** rather than hardcoding. The loader could compute `len(df_long)` at melt-time and use that as the verification baseline. Hardcoded magic numbers are a known anti-pattern in test/verification code; this is exactly the failure mode they cause.
- Carry-forward to Project #3.

### 2026-05-17 — Test-count drift in PROJECT_CONTEXT records

**Symptom:** Predicted full-DAG `dbt build` PASS=77 after shipping the mart. Actual: PASS=78. Off by one.

**Diagnosis:** Worked backwards through the targeted-build output (`mart_executive_overview` shipped 1 model + 10 tests = 11 PASS, correct) and the project totals (69 tests in YAMLs, also correct). The discrepancy traced to the *previous* session's PROJECT_CONTEXT record: session 4 close claimed `fact_daily_sales` shipped with 13 tests and the project total was 58. Actual YAML counts show 14 fact tests and 59 project tests at session-4 close. The eye-balled column-level tally missed the model-level `unique_combination_of_columns` test on the fact (model-level tests are easy to miss when scanning down a list of column-level `data_tests:` blocks).

**Fix:** Corrected the historical record in PROJECT_CONTEXT's session-5 closeout block (notes the 58 → 59 correction in-line). The 78-count is consistent with the corrected baseline (59 + 11 = 70 tests; 8 models + 1 mart = 9; 70 + 9 = wait, off again — actual is 78 = 69 tests + 9 models, so the math is: 58 → 59 at session 4, 59 + 10 = 69 today; total nodes 8 → 9 with the mart; 69 + 9 = 78 ✓).

**What this taught me:** When counting tests on a model, eyeballing the YAML's `data_tests:` blocks **misses model-level tests** that sit at the model's top level rather than under any column. Two reliable disciplines:

1. Run the targeted `dbt build` and read the count off the output line ("Finished running ... N data tests in ..."). The build is ground truth.
2. When grepping for test counts manually, search separately for `^[[:space:]]+-[[:space:]]+(unique|not_null)` (built-in column tests) AND for namespaced tests (`unique_combination_of_columns`, `accepted_range`, `relationships`) which can sit at column OR model level.

Caught by the phase-boundary structural audit on its second explicit application — paid for itself again.

### 2026-05-17 — Conflated Airflow page-level vs panel-level trash icons → deleted entire DAG history

**Symptom:** Tried to delete a single failed DAG run (the 2014-01-05 manual trigger that hit the incremental backfill limitation) by clicking the red trash icon in the top-right of the DAG page. Instead of deleting just the one run, the entire DAG disappeared from the DAG list. All run history wiped.

**Diagnosis:** Airflow's UI has **multiple trash icons at different scope levels** in different parts of the screen, and they look identical (small red trash can):

| Trash location | What it deletes |
|---|---|
| Top-right of the DAG page (next to play button, under user avatar) | **The entire DAG** — all runs, all task instances, all history |
| Inside the side panel when a Run is selected | Just that one DAG run |
| Inside the side panel when a Task is selected | Just that one task instance |

Claude conflated the page-level (top-right) trash with the panel-level (side panel) trash when guiding through the housekeeping step. Should have specified the panel-level location explicitly.

**Fix:** None needed for the actual code or data — the DAG **file** on disk (`airflow/dags/m5_daily_extract.py`) was untouched. Airflow only deleted the metadata-DB records. The scheduler re-parsed the DAG file on its next sweep (~30 seconds) and the DAG reappeared with zero history. Snowflake data also untouched.

**What was lost:** the run-history records from Phase 3 sessions (extract_one_day successes, the verify-caught-silent-failure episodes from session 2). The Grid view's coloured history bars no longer show those runs. Cosmetic loss — the lessons themselves survive in PROJECT_CONTEXT, in LEARNINGS, and in screenshots taken during the sessions.

**What this taught me:**

1. **Airflow's UI uses scope-sensitive icons.** Same icon (trash can) means different things depending on which part of the screen it's in and what's currently selected. When in doubt, click into the side panel first (select a specific Run or Task) and use the buttons there.
2. **For deleting individual runs cleanly**, the safer path is: select the run in side panel → use "Mark Failed" (closes out retries, marks the run failed) rather than the trash icon. The trash is for permanent metadata removal.
3. **For documentation / portfolio purposes**, leaving a failed run in history is often fine — the red square is meaningful evidence that "verify caught a problem." Only delete if cleanliness matters more than evidence.

**Carry-forward**: when guiding through any UI action, name the EXACT screen region the button is in, not just the button shape. "Red trash in the top-right corner" is ambiguous; "red trash inside the side panel that appears when you click on a Run" is unambiguous. This is a teaching-discipline lesson as much as an Airflow lesson.

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

### 2026-05-13 — Date-window filtering: fixed scan cost dominates per-row cost

**Observed during Phase 2 session 2 smoke tests:**

| Window | sales_train rows | Wall-clock |
|---|---|---|
| 1 day  | 30,490  | 126 sec |
| 7 days | 213,430 | 121 sec |

**The 7-day extract is faster than the 1-day extract.** Same source query shape (`WHERE d IN (?,?,...)`), just more values in the IN list. Reading 7x more data took *less* wall time.

**Diagnosis:** `raw.sales_train` has no index on the `d` column (we deliberately skipped clustering it — a synthetic string like `d_1142` doesn't sort to date order, so an index buys nothing). Every query against it does a full table scan over 59M rows. That scan cost is roughly fixed per query — it dominates the per-row read cost at small extract sizes.

**Implication for the upcoming backfill:**

The 3-year backfill (~32.5M sales_train rows, 1066 d values in the IN list) was originally feared at "~40 hours if it scales linearly with the daily run." It won't. It's one query, one scan, then bulk-streaming rows through pandas chunks to Snowflake's `write_pandas`. Estimated end-to-end: **60-90 minutes**, not 40 hours.

**General principle for any "should I extract day-by-day or in batches?" decision:**

If the source can't filter cheaply by your partition key (no index, or the column isn't naturally ordered), **a single wide-window query is cheaper than N narrow-window queries.** The Airflow daily run still works (the 2-minute cost is acceptable for a scheduled job), but backfills should always go wide.

**Why this won't bite us in Phase 3:** Airflow runs one date per scheduled invocation, paying the fixed ~70-second scan cost once per day. At 2.3 minutes per run × overnight, total compute is trivial. The pattern is fine; just don't naively *loop* an Airflow-style daily run for backfill.

**Validated 2026-05-14 (Phase 2 session 3):** The actual 3-year backfill completed in **27.3 minutes** (1,638 sec) end-to-end — comfortably inside the 60-90 min prediction and dramatically faster than the originally-feared 40 hours. The "one wide query, fixed scan cost dominates" pattern delivered as designed. Locks the pattern for future Project #3 backfills against any unindexed-source-to-warehouse pipeline.

### 2026-05-13 — `loaded_at` audit column on every Snowflake RAW table

**Considered:** Mirror the Azure SQL raw tables exactly — same columns, nothing else.

**Chosen:** Add `loaded_at TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP() NOT NULL` to all three RAW tables in Snowflake.

**Trade-off accepted:** Tiny divergence from Azure SQL shape (one extra column) in exchange for free lineage on every row. The `DEFAULT` means the extract script doesn't need to populate it — Snowflake stamps it on insert. No code complexity.

**Where it pays back:** Phase 3 "did the pipeline run today?" health checks (`SELECT MAX(loaded_at) FROM raw.sales_train`), debugging late-arriving rows, dbt source freshness tests. Standard practice in raw landing layers — cheap to add now, painful to retrofit.

### 2026-05-17 — Lean marts layer + analyst-facing star schema

**Considered:**

- **Wide-mart pattern (original plan).** Five marts, one per Power BI page, each denormalised with date attributes flattened in. Power BI reads what's there. Common in DE-heavy teams where engineers ship the modelling.
- **Lean-mart pattern.** Expose the warehouse star (fact + conformed dims) directly to Power BI. Build relationships and DAX measures in the BI tool. Marts only where they earn their keep — pre-aggregations for performance, or cross-domain joins that don't belong in any single fact.

**Chosen:** Lean-mart pattern. Start with **one** mart — `mart_executive_overview` — pre-aggregating `fact_daily_sales` (32.9M rows) down to ~1,148 daily summary rows. Add `mart_forecast_vs_actual` later in Phase 5 only when forecasts exist (joins two domains, genuinely earns a mart). Drop the four "thin re-projection" marts (Demand by Hierarchy / Promotion & Price / Seasonality & Calendar / etc.) — Power BI's VertiPaq engine handles those off the star directly, and pre-baking them adds maintenance weight without proportional value.

**Trade-off accepted:** Less pre-baked work in the warehouse means more modelling work in Power BI (relationships, DAX measures, slicer plumbing). That's the intended trade — Phil targets Melbourne BI Analyst / DE-adjacent roles where Power BI fluency matters as much as the pipeline behind it. The leaner shape lets the warehouse demonstrate clean DE patterns *and* leaves real BI work to demo.

**Risk-register revision:** The original "Power BI only ever connects to `marts/` — never raw or warehouse-fact" rule (Project Plan risk register) is **superseded**. New rule: Power BI connects to `WAREHOUSE.fact_*` + `dim_*` for analyst-facing pages, and to `MARTS.mart_*` for pre-aggregated/cross-domain pages. The risk of "Power BI choking on the 32.9M-row fact" is mitigated by VertiPaq's compression — a single XS Snowflake warehouse plus Power BI's in-memory engine handles this size comfortably. Verified empirically before relying on it in Power BI.

**Why this matters for the portfolio:** This is the most-professional architectural default for the role-shape Phil is targeting. The interview talk-track is sharper than "I built five marts because that's what the tutorial said":

> "I exposed the warehouse star directly to Power BI for analyst flexibility. The marts layer holds pre-aggregations only where they genuinely earn their keep — `mart_executive_overview` rolls 32.9M fact rows down to a daily summary for the dashboard home page. Sliceable rollups stay in Power BI's own model where analysts can iterate quickly."

**Carry-forward to Project #3:** When the question "should this go in a mart or a BI tool?" comes up, default to "BI tool" unless the mart earns its keep via (a) pre-aggregation that meaningfully speeds dashboard refresh, (b) cross-domain joins that don't belong in any single fact, or (c) governance/SLA reasons specific to that downstream consumer.

### 2026-05-17 — Extend Airflow DAG with dbt orchestration via Astronomer Cosmos

**Considered:**

- **Defer dbt orchestration to Project #3.** Keep Project #2's Airflow story at "I stood up the stack and wrote a first DAG (extract + verify)." Power BI handles refresh manually. Cheaper in the near term, but the headline DE deliverable (*end-to-end orchestrated pipeline*) is only half-built.
- **Extend the existing DAG via `BashOperator`.** Add one `dbt_build_one_day` task that shell-runs `dbt build`. Simplest possible. Works but doesn't impress — one opaque task fires either green or red with no per-model visibility.
- **Extend the existing DAG via Astronomer Cosmos.** Cosmos parses dbt's manifest at DAG-parse time and generates **one Airflow task per dbt model** with full dependency wiring. Each `stg_*` / `int_*` / `dim_*` / `fact_*` / `mart_*` model + its tests becomes its own Airflow task in the UI. The Airflow lineage graph shows the dbt DAG directly. Steeper setup; real-shop pattern.

**Chosen:** Astronomer Cosmos. Phase 4 session 6 (next) extends `m5_daily_extract.py` from 2 tasks to a 4-stage shape: `extract_one_day → verify_one_day → <Cosmos task group for dbt> → verify_dbt_one_day`. Power BI moves one session out to Phase 5.

**Trade-off accepted:** One additional session of work (~2-3 hours) and one new dependency (`astronomer-cosmos` in the Airflow image) in exchange for the headline DE deliverable being real: *the pipeline runs end-to-end on a schedule, with proper failure handling, tests, and per-model lineage visibility*. Without this, Project #2's orchestration story is foundation-only.

**Why this matters for the portfolio:** The Melbourne BI Analyst / DE-adjacent role-shape Phil is targeting weights orchestration heavily — recruiters and hiring managers reading the README want to see the full chain (extract → load → transform → test → publish) wired into a scheduler with proper failure handling. Cosmos is also the integration approach real shops use in 2025 (the dbt Cloud-native and Airflow-native options have largely converged on this pattern), so showing it in a portfolio repo demonstrates current-tooling fluency, not just conceptual understanding.

**Interview talk-track:**

> "I integrated dbt and Airflow via Astronomer Cosmos. Cosmos parses the dbt manifest at DAG-parse time and creates one Airflow task per dbt model — so the Airflow lineage graph shows the dbt model DAG directly, and a failure on a single model surfaces in the Airflow UI as a single red task with a link to the dbt logs. Cleaner observability than wrapping `dbt build` in a single `BashOperator`."

**Carry-forward to Project #3:** Default to per-model task generation (Cosmos or the equivalent for whatever orchestrator Project #3 uses — Dagster's dbt assets, Prefect's `prefect-dbt`, etc.) rather than monolithic shell-out, unless the dbt project is small enough that the manifest-parse overhead at DAG-parse time isn't worth the granularity.

---

## Pipeline orchestration

> Project #1 was manual. Project #2's headline is orchestration. This section
> captures the orchestration design and lessons learned implementing it.

The Project #2 orchestration story builds in two stages:

**Phase 3 (sessions 1-2): Airflow stack stood up; first DAG fires extract + verify.** Custom Airflow image extends `apache/airflow:2.10.3-python3.11` with the Microsoft ODBC driver and a minimal `requirements-airflow.txt` (pyodbc, python-dotenv, snowflake-connector-python). Postgres metadata DB, LocalExecutor, three Airflow services (init, webserver, scheduler) via docker-compose. The first DAG (`m5_daily_extract`) wraps the existing `scripts/extract_azure_to_snowflake.py` as a single @task at `@daily` cadence, with a downstream `verify_one_day` @task that independently queries Snowflake to confirm rows landed. Caught a real silent failure on its first auto-fire (no M5 data for 2026-05-15; verify went red within 10 minutes of deployment).

**Phase 4 session 6: dbt orchestration wired in via Astronomer Cosmos.** The two-task chain becomes a four-stage chain: `extract_one_day → verify_one_day → [dbt_models task group, 18 auto-generated tasks] → verify_dbt_one_day`. Cosmos reads the dbt project at DAG-parse time and generates one Airflow task per dbt model + per test; the Graph view shows the dbt DAG directly. Failure injection test confirmed the chain halts cleanly on dbt test failure (upstream_failed propagation, no broken-data verifications fire downstream).

**The headline number**: 13 lines of Cosmos config in the DAG replace what would have been ~150 lines of hand-wired `BashOperator` tasks. Single source of truth (the dbt project), automatic regeneration at every DAG-parse, per-model lineage in the Airflow UI.

**The headline talk-track**: *"end-to-end pipeline on a schedule, with proper failure handling, tests, and per-model lineage visibility. A broken dbt test halts the chain at exactly that task, the downstream verify never fires on broken data, and the Airflow UI tells me which model in which layer broke without grepping logs."*

**Carry-forward principles for Project #3**:

1. Always run a downstream "verify" task immediately after a load / transform task. Don't trust the task's own success report — independently query the destination and confirm row counts at the layer being written. This caught a real silent failure on its first day of operation in Project #2.
2. Per-model task generation > monolithic shell-out for orchestrating dbt under any scheduler. Cosmos for Airflow; Dagster's dbt assets for Dagster; `prefect-dbt` for Prefect. The portfolio screenshot of "Airflow Graph view showing my dbt DAG directly" is the headline visual that recruiters respond to.
3. Failure-injection tests as closing validation of every orchestration chain. Flip one value, trigger, observe the clean halt, revert. Produces a credible "yes, the failure path actually works" demonstration.
4. Keep one credential surface (the project-root `.env`) shared between local development and the deployed container env, via `env_var()` in profiles.yml and `env_file:` in docker-compose. One source of truth for secrets, two execution environments.

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
