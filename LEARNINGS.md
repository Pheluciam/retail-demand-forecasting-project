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
