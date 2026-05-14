# Code Quality Standards

> A personal engineering checklist applied to every non-trivial script in this
> project. Built up during Project #1 and formalised at the start of Project #2's
> Phase 1.
>
> The goal is **methodical first-pass quality** — catching cost, security, and
> contract issues before they reach a code review or production. Re-work is the
> most expensive part of a data pipeline; this checklist exists to minimise it.

---

## The seven core checks

Applied before any script — SQL or Python — is considered "done":

### 1. Currency

Code uses **current, supported idioms** of the language or SQL dialect. Deprecated patterns are replaced when modern equivalents exist on the deployment target.

**Examples in this repo**

- `DROP TABLE IF EXISTS raw.sales_train;` (SQL Server 2016+ syntax) used in `sql/ddl/01_create_raw_tables.sql`, rather than the pre-2016 `IF OBJECT_ID(...) IS NOT NULL` form
- `pathlib.Path` used throughout Python scripts, not `os.path` string concatenation
- f-strings, never `.format()` or `%s`
- pyodbc 5.x with explicit `autocommit=True` for DDL batches

### 2. Compactness

Concise without sacrificing readability. No clever golf, no unnecessary lines.

**Examples in this repo**

- Single-line list comprehension to filter empty SQL batches: `[b.strip() for b in batches if b.strip()]` instead of a 5-line loop
- Connection strings built once, reused — never duplicated across scripts

### 3. Resource efficiency (cost-aware)

Every script is sized to use the minimum CPU, memory, network, and storage needed. Cloud-cost-aware design from the start, not retrofitted.

**Examples in this repo**

- `WITH (DATA_COMPRESSION = PAGE)` on `raw.sales_train` (~59M rows) and `raw.sell_prices` (~6.8M rows). Estimated 50–70% disk savings — material on the Free Serverless tier's 32 GB cap.
- Column types sized to actual content: `TINYINT` for 0/1 SNAP flags, `SMALLINT` for `year`, `NVARCHAR(5)` for `state_id`. No `BIGINT` or `NVARCHAR(MAX)` where smaller types fit.
- No indexes on raw tables — bulk load runs faster, query-side performance lives in the dbt warehouse layer where it belongs.
- `Connection Timeout=90` tuned to Free Serverless auto-pause behaviour (see `LEARNINGS.md`) — not an arbitrary larger-is-safer default.

### 4. Privacy & security

Secrets externalised, transport encrypted, certificates validated, no sensitive data leaking into logs.

**Examples in this repo**

- All credentials in `.env` (gitignored). `.env.example` committed as a template with placeholder values.
- Every Azure SQL connection uses `Encrypt=yes; TrustServerCertificate=no` — TLS in transit with proper certificate-chain validation.
- Connection timeouts bounded to prevent hanging connections.
- No passwords or PII printed by any script.
- No string-concatenated SQL — zero SQL-injection surface.

### 5. Workflow consistency

Code matches the project's own conventions and the platform conventions of its eventual deployment target.

**Examples in this repo**

- `snake_case` everywhere — tables, columns, scripts, schemas. Matches the Snowflake target (Phase 2) and dbt convention (Phase 4).
- `NVARCHAR` (not `VARCHAR`) for every string column — Unicode-safe, carry-forward from Project #1's encoding lessons.
- `raw` schema in Azure SQL mirrors the planned `RAW` schema in Snowflake — same mental model both sides of the extract.
- File layout: `sql/ddl/` for DDL, `scripts/` for Python — predictable for any reviewer.

### 6. Dev environment hygiene

The local development environment fully validates the code before commit. Linter and type-checker output is treated as signal, not noise — if it's yellow, it gets addressed (fixed, or explicitly suppressed with a documented reason). Drift between "what the linter sees" and "what gets committed" is the same silent-bug class the rest of this checklist exists to prevent.

**Examples in this repo**

- `pyrightconfig.json` at the project root with `extraPaths: ["scripts"]` so Pylance can resolve the DAG-side `import extract_azure_to_snowflake` against the actual module on the host.
- `apache-airflow==2.10.3` installed locally with `--no-deps` so the IDE finds `from airflow.decorators import dag, task` without dragging in Windows-incompatible Unix daemons.
- `# type: ignore` used only as a last resort, with a comment explaining *why* it's there — never to paper over fixable issues.

**How this got here**

Added 2026-05-14, mid-Phase-3-session-1. Yellow squigglies on `airflow/dags/m5_daily_extract.py` surfaced that the original nine criteria all audited the code itself; none covered the environment around it. The checklist evolves when we find gaps — full diagnosis in `LEARNINGS.md`.

### 7. Upstream / downstream contract

Inputs match what the upstream source actually produces (verified, not assumed). Outputs match what downstream consumers expect. No mid-pipeline rework caused by a type mismatch that could have been caught up front.

**Examples in this repo**

- Before writing the loader, CSV headers were inspected directly (`head -1 calendar.csv` etc.) to confirm column names and ordering matched the DDL — no surprises during the load.
- `raw.calendar.d` and `raw.sales_train.d` both `NVARCHAR(10)` — join key types match by design.
- `DECIMAL(10,4)` chosen for `sell_price` rather than `FLOAT` — preserves exact monetary values through pandas → Snowflake → dbt without binary-rounding drift.
- Case-sensitivity differences between Azure SQL (case-insensitive default) and Snowflake (case-sensitive default) flagged ahead of Phase 2 extract design — no surprise on the receiving end.

---

## Three additional failsafes

Layered in by default on every non-trivial script:

### 8. Idempotency

Every script can be re-run after a partial failure without orphaned state or accidental duplicates.

**Examples in this repo**

- DDL uses drop-and-recreate — `sql/ddl/01_create_raw_tables.sql` is safe to re-run during schema iteration.
- (Phase 1 loader, in progress) Will TRUNCATE-then-INSERT for each table — a failed mid-run leaves zero ghost rows.

### 9. Pre-flight and post-action verification

Validate assumptions before destructive work. Confirm the outcome after.

**Examples in this repo**

- `scripts/smoke_test_azure_sql.py` proves the full connection stack (pyodbc → ODBC Driver 17 → TLS → firewall → Azure SQL auth) before any data work begins.
- `Test-NetConnection ... -Port 1433` used as a network-only diagnostic to distinguish firewall failures from login-layer failures.
- `scripts/load_m5_to_azure_sql.py` compares actual row counts against expected values post-load — raises `ValueError` on any mismatch.
- `sql/verify/01_phase1_load_verification.sql` — a separate, version-controlled SQL file containing the 5-section verification suite for Phase 1 (row counts, schema, sample rows). Standalone artefact you can re-run any time, not just at load time.

**Caveat from Phase 1 (what *not* to do):**

The loader's `EXPECTED_ROWS` constant for `sales_train` was a hardcoded magic number — and it was wrong by 1,000. Result: an 11-hour load that completed correctly but exited with a false `MISMATCH` alarm. The verification *logic* was perfect; the *expected baseline* was wrong.

**Lesson:** verifying the SHAPE of a calculation is not verifying the PRODUCT. When a magic number guards verification, compute it via two independent routes (Python arithmetic AND `SELECT 30490 * 1941` in SQL), or — better — derive the expected value from runtime measurements instead of hardcoding. The full diagnosis is in `LEARNINGS.md` under *Mistakes & diagnoses*.

### 10. Observable progress and actionable errors

Long-running operations report what they are doing. Failures surface specifics, not raw tracebacks.

**Examples in this repo**

- Both Python scripts print batch-by-batch progress (`Batch 3/5: CREATE TABLE raw.sell_prices...`).
- The connect step explicitly warns about Free Serverless auto-pause: *"If the database has auto-paused, the first connect may take 30–60 seconds..."* — operator knows it's not frozen.

---

## Why this checklist exists

In any production pipeline, the most expensive defects are the ones caught **after** code has been deployed and data has flowed: re-loads, schema migrations, downstream model rewrites, broken dashboards, stakeholder emails. The checklist is upfront discipline aimed at moving as many of those decisions as possible into **first-pass authoring** — when the cost of changing a column type or compression setting is one edit, not a rollback.

The structure of this project is deliberately documentation-heavy in support of this principle:

- `PROJECT_PLAN.md` — locks scope and decisions up front
- `LEARNINGS.md` — captures every "diagnosis → fix → what this taught me" loop
- `CODE_QUALITY.md` *(this file)* — the bar every script is held to
- `TEACHING_PREFERENCES.md` — how I work with AI tooling that helps enforce all of the above

---

*Last updated: 2026-05-14 (Phase 3 session 1 — added criterion 6, Dev environment hygiene). First applied to Phase 1 deliverables: `smoke_test_azure_sql.py`, `01_create_raw_tables.sql`, `create_raw_tables.py`.*
