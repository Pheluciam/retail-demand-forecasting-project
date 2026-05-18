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
