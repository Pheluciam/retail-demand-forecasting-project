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

## Phase-boundary structural audit

Beyond the per-script 10-point audit, a structural pass is applied at each
**phase or layer boundary** — before a phase is declared "done" and before
the next phase begins. The per-script audit verifies that individual files
meet the bar; the structural audit verifies that the project **as a
collection** is consistent, complete, and free of drift.

### Why this exists

The per-script audit can miss issues that only appear in aggregate:

- **Naming collisions** — two files in the same folder sharing a numeric
  prefix (e.g. two `04_*.sql` verify files). Each file is fine on its own;
  together they break monotonic ordering.
- **Stale scaffolding** — `.gitkeep` placeholders left behind after their
  folders gained real files. Each individual `.gitkeep` is harmless; the
  pattern across the project is redundant noise.
- **Missing pairings** — a `.sql` model without its schema-YAML entry; a
  verify file whose model has been renamed; a test referencing a column that
  no longer exists.
- **Test-count drift** — schema YAMLs and the actual `dbt build` test count
  diverge silently when models are added or refactored without updating
  tests.

The cheapest place to catch these is at the **end of each phase**, before
documentation closeout and before the bundled commit lands.

### What to check

| Check | Question |
| --- | --- |
| File inventory | All expected files present (`.sql`, schema YAML, sources, verify, walkthrough)? |
| Naming monotonicity | File prefixes order monotonically; no collisions? |
| Scaffolding cleanup | `.gitkeep` only in folders that are still empty? |
| Pairings | Every model has a schema entry; every verify file has a live model |
| Test-count parity | Schema-YAML test count matches `dbt build` test count |
| Doc currency | Walkthrough doc covers every model in the layer; PROJECT_CONTEXT's file lists are accurate |

### When to run

- At the **end of each phase session** that ships meaningful structure
  (Phase 1 load layer, Phase 2 extract layer, Phase 3 DAG layer, Phase 4
  each dbt layer, etc.)
- **Before** drafting closeout docs — findings can be fixed in-session
  rather than back-and-forth'd in a follow-up commit
- **Before** the bundled commit — keeps the commit a clean snapshot, not
  a mix of work + retrospective cleanup

### How

A quick `Glob` or `ls -1` over the relevant folders enumerates files; a
mental walk-through against the checklist above surfaces drift. Fixes
applied in-session, then proceed to docs + commit.

### First explicit application: Phase 4 session 4 (2026-05-16)

Caught two issues that would otherwise have been frozen into the session
commit:

1. `04_phase4_int_sales_with_prices_verification.sql` collided with
   `04_phase4_staging_layer_verification.sql` — both prefixed `04_`. Renamed
   the intermediate one to `04a_` to preserve monotonic ordering without
   renumbering downstream verify files.
2. Three stale `.gitkeep` placeholders still in `staging/` /
   `intermediate/` / `warehouse/` model folders despite those folders
   now containing real models. Removed; only `marts/.gitkeep` remains
   pending session 5.

Both were 30-second fixes once caught. The cost of catching them
post-commit would have been a rebase or a follow-up "fix" commit — more
disruptive, worse history. The audit paid for itself on its first run.

### Phase 6 audit (2026-05-22) — v1.0 ship gate

Three new files shipped at Phase 6 close. Each passed all 10 criteria; results banked below for v1.0 release notes.

**`.github/workflows/lint-python.yml`** — ruff F821 CI gate.

- Currency: actions/checkout@v4 + actions/setup-python@v5 (latest stable as of May 2026); Python 3.11 baseline matches local venv.
- Compactness: 30 lines; comments explain why F821-only scope is correct (full ruff is gold-plating).
- Resource efficiency: lint runs in milliseconds; no Docker pull, no DB connection.
- Privacy & security: no secrets needed, no credentials referenced.
- Workflow consistency: kebab-case workflow filename matches the sibling dbt-ci.yml.
- Dev environment hygiene: Python version pinned; pip install ruff without version pin is acceptable for a single-rule check.
- Upstream/downstream contract: F821 catches exactly the class of bug surfaced at 5.9 (`mart_rows` stale variable reference). Defense-in-depth, not primary defence.
- Idempotency: re-runs are safe; lint is read-only.
- Pre-flight + post-action verification: the workflow IS the pre-flight verification step for every PR.
- Observable progress + actionable errors: ruff outputs `file:line:col` for each finding, directly actionable.

**`.github/workflows/dbt-ci.yml`** — dbt parse + sqlfluff lint.

- Currency: dbt-core 1.11.10 + dbt-snowflake 1.11.5 pins match `requirements.txt` exactly; sqlfluff >=3.0.0 modern.
- Compactness: two-job workflow; inline comment block explains why `dbt test` is deliberately excluded from CI (cost avoidance on pay-as-you-go Snowflake).
- Resource efficiency: `paths:` filter limits runs to `dbt/**` changes — no wasted CI minutes on README-only commits.
- Privacy & security: dummy env vars in the job (not real secrets); `dbt parse` doesn't connect to Snowflake.
- Workflow consistency: matches sibling lint-python.yml style and conventions.
- Dev environment hygiene: pins exactly match `requirements.txt`; `defaults.run.working-directory: dbt` removes path duplication.
- Upstream/downstream contract: matches dbt-snowflake adapter version the project ships with.
- Idempotency: re-runs safe.
- Pre-flight + post-action verification: dbt parse catches Jinja / ref / source errors; sqlfluff catches SQL style drift.
- Observable progress + actionable errors: both tools emit file:line errors with rule codes; failures point directly at the offending model.

**`dbt/.sqlfluff`** — Snowflake-dialect lint config.

- Currency: snowflake dialect + jinja templater are sqlfluff's current canonical names; `apply_dbt_builtins = true` enables `ref()` / `source()` / `var()` macro recognition.
- Compactness: 30 lines; every section commented; each rule exclusion individually rationalised inline.
- Resource efficiency: no DB connection required for lint; runs entirely on local templating.
- Privacy & security: no secrets in config; no credentials referenced.
- Workflow consistency: keyword case `upper` matches Phil's explicit SQL preference from TEACHING_PREFERENCES.md; identifier case `lower` matches dbt model source code; type/function/literal cases match conventional Snowflake style.
- Dev environment hygiene: 120-char line length accommodates typical dbt-generated SQL without forcing artificial wrapping.
- Upstream/downstream contract: dialect matches what the dbt project actually emits.
- Idempotency: configuration is declarative; same input → same output every run.
- Pre-flight + post-action verification: this config IS the gate sqlfluff uses for lint verification.
- Observable progress + actionable errors: rule exclusions documented explain WHY each is off, so future engineers can re-enable confidently.

**No findings to fix.** The Phase 4 audit caught 2 issues; this Phase 6 audit caught 0. Different file class — Phase 4 was author-time SQL + Python scripts where ordering / placeholder management could drift; Phase 6 is single-purpose CI declarations where the entire surface is small and reviewable in one pass. Net: 10-criteria checklist proven applicable across both file classes.

---

## Why this checklist exists

In any production pipeline, the most expensive defects are the ones caught **after** code has been deployed and data has flowed: re-loads, schema migrations, downstream model rewrites, broken dashboards, stakeholder emails. The checklist is upfront discipline aimed at moving as many of those decisions as possible into **first-pass authoring** — when the cost of changing a column type or compression setting is one edit, not a rollback.

The structure of this project is deliberately documentation-heavy in support of this principle:

- `PROJECT_PLAN.md` — locks scope and decisions up front
- `LEARNINGS.md` — captures every "diagnosis → fix → what this taught me" loop
- `CODE_QUALITY.md` *(this file)* — the bar every script is held to
- `TEACHING_PREFERENCES.md` — how I work with AI tooling that helps enforce all of the above

---

*Last updated: 2026-05-22 (Phase 6 close — v1.0 ship audit appended; 3 new CI files passed all 10 criteria, 0 findings). Prior milestones: 2026-05-16 (Phase 4 session 4 — added "Phase-boundary structural audit" section; first applied in this session and caught two real findings); 2026-05-14 (Phase 3 session 1 — added criterion 6, Dev environment hygiene). First applied to Phase 1 deliverables: `smoke_test_azure_sql.py`, `01_create_raw_tables.sql`, `create_raw_tables.py`.*
