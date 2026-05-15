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

### Airflow

**Stack architecture choices (2026-05-14, Phase 3 session 1)**

- **Self-contained `airflow/` subdirectory.** Everything Airflow-related — `docker-compose.yml`, the custom `Dockerfile`, `requirements-airflow.txt`, `dags/`, `plugins/`, `logs/` — lives under one folder. Project root stays clean. The compose file mounts the parent project's `scripts/` folder read-only into the containers so the DAG can call the existing `extract_azure_to_snowflake.py` without code duplication.
- **LocalExecutor, not CeleryExecutor.** Airflow has several "executor" engines deciding how tasks actually run. LocalExecutor runs each task as a subprocess on the scheduler container — adequate for a single-DAG portfolio project. CeleryExecutor adds a Redis broker plus N worker containers — required at production scale, overkill here. Worth knowing the upgrade path exists: same DAG code, just swap executor + add services in compose.
- **Four containers in the stack.** `postgres` (Airflow's own metadata DB, not our retail data), `airflow-init` (one-shot bootstrap that runs `airflow db migrate` and creates the admin user, then exits), `airflow-webserver` (UI at `localhost:8080`), `airflow-scheduler` (parses DAGs, schedules + runs tasks). Init `depends_on: postgres: condition: service_healthy`; webserver and scheduler `depends_on: airflow-init: condition: service_completed_successfully` — ordered startup is declarative.
- **One `.env`, two execution environments.** `env_file: - ../.env` in the compose anchor passes our existing Azure SQL + Snowflake creds into every Airflow container as env vars. The extract script's `os.getenv("AZURE_SQL_SERVER")` calls work identically inside Airflow and from PowerShell — zero environment-specific branching in our code. One source of truth for secrets.

**Custom Airflow image — never reuse the project-root `requirements.txt` (2026-05-14, Phase 3 session 1)**

Two-stage failure during the first build of the custom Airflow image. Worth capturing both stages because each one teaches something separate.

- **Stage 1 — no `--constraint` flag, install our `requirements.txt` directly.** Build succeeded. Then the `airflow-init` container immediately crashed at runtime with `sqlalchemy.orm.exc.MappedAnnotationError: Type annotation for "TaskInstance.dag_model" can't be correctly interpreted for Annotated Declarative Table form.` Diagnosis: Airflow 2.10 needs SQLAlchemy **1.4.x**. Our `requirements.txt` has `sqlalchemy>=2.0.0`. pip happily upgraded SQLAlchemy past what Airflow could handle. The base image worked, our pip step broke it.
- **Stage 2 — same `requirements.txt`, now with `--constraint` pointing at Airflow's official constraints file.** Build failed at the pip step with a dependency-resolution error. Why: the constraint says "SQLAlchemy must be 1.4.x", our requirement says "SQLAlchemy must be ≥ 2.0.0" — pip refuses to resolve a direct conflict rather than silently picking one. So `--constraint` alone wasn't enough; the underlying disagreement between our requirements file and Airflow's needs still had to be fixed.

**The fix that worked: separate `airflow/requirements-airflow.txt` with no version pins.** Lists only the extras our extract script needs that aren't already in the Airflow base image (`pyodbc`, `python-dotenv`, `snowflake-connector-python[pandas]`). The `--constraint` flag pointed at `https://raw.githubusercontent.com/apache/airflow/constraints-2.10.3/constraints-3.11.txt` then chooses tested versions for everything. Build clean, runtime clean.

**General principle for any custom image extending an opinionated base.** Don't blanket-apply your existing pin lists onto an image whose maintainers have already thought hard about compatible versions. List only the *additional* packages you need, leave them unpinned, and let the base image's constraints/lockfile decide versions. Same lesson would apply to a custom `dbt-core` Docker image, a custom Jupyter image, or anything else where you're layering deps onto a curated stack.

**Mistakes & diagnoses carry-forward:** add "look at constraints/lockfile of base image before adding deps" to the Code-Quality checklist as an implicit corollary of criterion 1 (Currency). Also a Project #3 carry-forward — most production Docker images extend an opinionated base.

**Docker daemon must be running before `docker compose` (2026-05-14, Phase 3 session 1)**

Trivial-in-hindsight but worth noting because the error message is opaque: `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine`. That long path is Docker Desktop's named pipe on Windows. The error is just "Docker Desktop isn't running." Fix: open Docker Desktop from the Start menu, wait for the whale icon in the taskbar to stop animating (settles to solid), then retry. The CLI (`docker`, `docker compose`) is a thin client that talks to a background service — the service has to be alive for any command to work.

**Code-quality framework gap discovered: dev environment hygiene (2026-05-14, Phase 3 session 1)**

Mid-session, yellow Pylance squigglies appeared on the freshly-written DAG file (`airflow/dags/m5_daily_extract.py`) — `import pendulum`, `from airflow.decorators import dag, task`, `import extract_azure_to_snowflake`. Phil pushed back: shouldn't `CODE_QUALITY.md` have flagged this kind of issue *before* it became a problem?

**Diagnosis.** The lunch audit had been run thoroughly against all nine criteria. But every one of those criteria audits what's *inside* the code — idioms, security, types, idempotency, observability. None audited the *dev environment around* the code — whether the local IDE could fully validate the file before commit. A clean genuine gap in the framework, not a memory miss or audit-execution miss.

**Fix.** Three coordinated edits, treating this as a process-improvement moment:

- **Added criterion 6 to `CODE_QUALITY.md`: "Dev environment hygiene."** Linter warnings zero-tolerance, IDE imports resolve to the same modules the runtime uses, local venv mirrors deployed environment, gaps documented when full local install isn't viable (Windows-incompatible deps, etc.).
- **Renumbered the rest of the checklist** (existing 6→7, 7→8, 8→9, 9→10) and updated section heading from "six core checks" to "seven core checks."
- **Mirrored the same change in `TEACHING_PREFERENCES.md`** which carries the abbreviated checklist alongside it — the two stay in sync.

**Practical-fix corollary.** While the framework was being updated, the actual yellow squigglies were addressed with the canonical Windows-host workaround:

- `pip install pendulum "apache-airflow==2.10.3" --no-deps` — installs the Airflow package source files into the local venv so Pylance can resolve `airflow.decorators` imports, without dragging in the 100+ Unix-only transitive dependencies that don't work on Windows native.
- `pyrightconfig.json` at project root with `extraPaths: ["scripts"]` — tells Pylance the DAG's runtime `sys.path.insert(0, "/opt/airflow/scripts")` corresponds to the host's `scripts/` folder, so `import extract_azure_to_snowflake` resolves cleanly.
- *Truly* professional answer for Windows-host DE work is **VS Code Dev Containers** (editor attaches to the running container; zero drift). Flagged as a Phase 6 polish item — strong interview talking point about progression from pragmatic-now to modern-later.

**What this taught me.**

- A code-quality checklist is a living artefact. Its value is in catching mistakes; the moment a mistake bypasses it, the checklist itself is the artefact to improve. Updating the checklist alongside the fix is the move that pays compounding interest across all future projects.
- "Code quality" and "dev environment quality" are distinct concerns and both deserve explicit criteria. Conflating them means dev-env issues hide as random IDE complaints rather than being treated as the same class of "drift creates silent bugs" risk that the rest of the checklist guards against.
- Carry-forward to Project #3: criterion 6 (Dev environment hygiene) starts from day one — pyrightconfig, IDE-resolves-runtime imports, linter-warnings-zero-tolerance baked into Phase 0 scaffolding.

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

Built `verify_one_day` as a second task in `m5_daily_extract`, downstream of `extract_one_day`. Three Snowflake-side checks (`CALENDAR` = exactly 1 row for run_date, `SELL_PRICES` > 0 rows for the fiscal week containing run_date, `SALES_TRAIN` > 0 rows for the M5 d-code mapping to run_date) batched into a single SQL round-trip with three positional `%s` binds. Doesn't read the extract task's return value or XCom — queries Snowflake fresh. Same philosophy as the files in `sql/verify/`, but the loop closes inside Airflow rather than relying on a manual Snowsight pass.

**The verify task caught a real silent failure within ten minutes of deployment.** While testing the manual `2014-01-03` trigger, the run stuck in `queued` forever. Diagnosis: **paused DAGs don't execute manually-triggered tasks in Airflow 2.x** — the trigger creates the DAG run successfully but the scheduler refuses to process tasks. Unpaused the DAG to clear it. The unpause then auto-fired today's `2026-05-15` slot because `catchup=False` only suppresses *historical backfill*, not the "next scheduled interval." Today's slot extracted data for a date M5 doesn't cover — Azure SQL returned 0 rows, `extract_one_day` finished cleanly with no error, and `verify_one_day` then asked Snowflake "got 1 calendar row for 2026-05-15?", got `0`, raised `RuntimeError`, square went red. **Exactly the silent-failure shape the verify task was designed to catch.**

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
