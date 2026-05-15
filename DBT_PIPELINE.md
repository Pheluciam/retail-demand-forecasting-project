# DBT_PIPELINE.md — dbt Transformation Pipeline Walkthrough

> Companion to `EXTRACT_PIPELINE.md`. This doc explains the dbt project that
> transforms RAW Snowflake data into the analytical layers that power Power BI.
>
> Last updated: 2026-05-15 (Phase 4 session 1).

---

## What dbt does in this project

After Airflow extracts M5 data from Azure SQL and lands it in `RETAIL_DB.RAW`,
dbt takes over. Every transformation from that point forward is a SQL file
under `dbt/models/`. dbt compiles each file, sends the SQL to Snowflake over
HTTPS, and Snowflake builds the resulting tables and views.

**Key mental model.** dbt itself does no data processing. It is a SQL templating
and orchestration tool that runs on your laptop. The actual compute happens
inside Snowflake. Your laptop sends `CREATE OR REPLACE VIEW … AS …` statements
over the wire; Snowflake executes them and materializes the objects.

---

## The five-layer architecture

```
RETAIL_DB.RAW          ← loaded by Airflow (existing, Phase 2/3)
        ↓
RETAIL_DB.STAGING      ← dbt: rename, type cast, lightweight cleaning
        ↓
RETAIL_DB.INTERMEDIATE ← dbt: business-logic joins and derivations
        ↓
RETAIL_DB.WAREHOUSE    ← dbt: Kimball star schema (fact_*, dim_*)
        ↓
RETAIL_DB.MARTS        ← dbt: pre-aggregated tables, one per Power BI page
```

Each layer is a Snowflake schema in the same `RETAIL_DB` database. dbt creates
each schema on its first build if it does not already exist.

**Layer responsibilities (full discipline):**

- **Staging (`stg_*`).** One model per source table. Renames columns to
  snake_case conventions, casts to proper types, NULLs out sentinel values.
  **No business logic, no joins to other sources.** Insulates downstream
  models from source-side changes.
- **Intermediate (`int_*`).** Joins across staging tables to assemble
  business concepts (e.g. sales-with-prices, calendar-aligned-events).
  Usually views.
- **Warehouse (`fact_*`, `dim_*`).** Kimball star schema. Surrogate keys
  via `dbt_utils.generate_surrogate_key`. Facts are partitioned and
  built incrementally for cost reasons.
- **Marts (`mart_*`).** One mart per Power BI page. Pre-aggregated and
  flattened so Power BI's DAX layer stays simple and queries stay fast.

---

## Project layout

```
dbt/
├── dbt_project.yml         ← master config
├── profiles.yml            ← Snowflake connection (env_var-driven)
└── models/
    ├── staging/            ← stg_m5_calendar, stg_m5_sell_prices, stg_m5_sales_train
    ├── intermediate/       ← int_* models (later phases)
    ├── warehouse/          ← fact_daily_sales, dim_item, dim_store, dim_calendar
    └── marts/              ← mart_<page_name> per Power BI page
```

---

## `dbt_project.yml` — what each section does

The master config is intentionally lean for portfolio readability. The full
shape is documented here so readers don't need to consult dbt docs.

### Project identity

```yaml
name: "retail_demand_forecasting"
version: "1.0.0"
config-version: 2
```

- `name` — the dbt project's internal handle. snake_case. Must match the
  top-level key under `models:` further down the file.
- `version` — semantic version of *this dbt project* (not dbt itself).
  Bumped manually when models change shape.
- `config-version: 2` — schema version of this YAML file. Always `2` for
  any modern dbt project. Locked since dbt 0.21.

### Connection profile pointer

```yaml
profile: "retail_demand_forecasting"
```

This is a *reference*. dbt looks for a top-level key called
`retail_demand_forecasting` in `profiles.yml` to find the Snowflake
credentials. `dbt_project.yml` says **what** to do; `profiles.yml` says
**where** to connect.

### Folder paths

```yaml
model-paths:    ["models"]
seed-paths:     ["seeds"]
test-paths:     ["tests"]
analysis-paths: ["analyses"]
macro-paths:    ["macros"]
snapshot-paths: ["snapshots"]
```

All six are dbt defaults — listed explicitly so the file shows the whole
shape of a dbt project at a glance. The square brackets are YAML's inline
list syntax; each setting *could* take multiple folders, but we only use
one each.

| Path | Folder | What goes there |
|---|---|---|
| `model-paths` | `models/` | The actual SELECT statements (`.sql` model files) |
| `seed-paths` | `seeds/` | Reference CSVs that `dbt seed` loads as small lookup tables |
| `test-paths` | `tests/` | Singular SQL tests — standalone queries that return 0 rows on pass |
| `analysis-paths` | `analyses/` | Ad-hoc investigative SQL; compiled but not run |
| `macro-paths` | `macros/` | Reusable Jinja macros — SQL "functions" |
| `snapshot-paths` | `snapshots/` | SCD Type 2 snapshot definitions for slowly-changing dimensions |

### Runtime artefacts

```yaml
target-path: "target"
clean-targets:
  - "target"
  - "dbt_packages"
```

- `target-path` — where dbt writes compiled SQL plus run logs after
  `dbt run`. Gitignored at project root.
- `clean-targets` — folders that `dbt clean` will delete. Used to wipe
  state and start fresh when something gets confused.

### Materialization defaults

```yaml
models:
  retail_demand_forecasting:
    staging:
      +materialized: view
    intermediate:
      +materialized: view
    warehouse:
      +materialized: table
    marts:
      +materialized: table
```

Sets the default materialization for every model in each folder. Individual
models override with `{{ config(materialized='...') }}` at the top of the
SQL file.

**The `+` prefix** is dbt's YAML syntax for "this is a config value, not
a sub-folder name." Without it, dbt would think `materialized` was a
sub-folder of `staging/`.

**Layer-by-layer reasoning:**

| Layer | Materialization | Why |
|---|---|---|
| Staging | `view` | Cheap, always fresh, no storage cost. Re-runs against RAW on every query. |
| Intermediate | `view` | Same reasoning as staging. Light cost, always reflects upstream state. |
| Warehouse | `table` (override `fact_*` to `incremental`) | Dims are small enough to rebuild every run; facts are too large — incremental only inserts new rows. |
| Marts | `table` | Power BI queries these — needs to be fast. Rebuilt on every dbt run. |

---

## `profiles.yml` — Snowflake connection

dbt finds connection details by looking up the `profile:` key from
`dbt_project.yml` inside `profiles.yml`. The two-file split is deliberate:
`dbt_project.yml` says *what* to do; `profiles.yml` says *where* to connect.

### File location

dbt searches for `profiles.yml` in this order:

1. `--profiles-dir` flag passed to the CLI.
2. `DBT_PROFILES_DIR` environment variable.
3. The current dbt project directory (when invoked from `dbt/`).
4. `~/.dbt/profiles.yml` (the dbt-community default — outside the repo).

This project uses option 3. The file lives at `dbt/profiles.yml`, so running
any dbt command after `cd dbt` picks it up automatically. Keeping the file
in the repo means a portfolio visitor can see exactly how dbt is wired to
Snowflake.

### Secrets handling — `env_var()`

No plaintext credentials in the file. Every credential is read from the shell
environment at run time using dbt's Jinja `env_var()` function:

```yaml
password: "{{ env_var('SNOWFLAKE_PASSWORD') }}"
```

The shell environment is populated from `.env` *before* running dbt. This
means:

- `profiles.yml` is safe to commit (no secrets in it).
- Rotating a credential = editing `.env`, not the YAML.
- Same pattern real teams use in production with HashiCorp Vault or AWS
  Secrets Manager — swap the secret source, dbt-side wiring stays identical.

### Loading `.env` into the PowerShell session before running dbt

dbt does **not** automatically read `.env`. The values must already be in
the shell environment when dbt starts. One-time-per-PowerShell-session load:

```powershell
# From project root
Get-Content .env | ForEach-Object {
    if ($_ -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}
```

After this runs, all subsequent commands in that PowerShell session
inherit the variables. dbt's `env_var()` calls resolve correctly.

### Targets

`profiles.yml` can define multiple "targets" — each one a complete set of
connection details. We have one: `dev`. A real team would add `prod` with
separate creds and a different default schema. Switch with
`dbt run --target prod`.

### Schema configuration — placeholder, fixed before any model materializes

The `schema:` field currently points at `RAW` via `SNOWFLAKE_SCHEMA`. This
is a placeholder. dbt models should NOT materialize in `RAW` (that's the
source schema). Before any `dbt run`, the proper layer-specific schemas
(STAGING / INTERMEDIATE / WAREHOUSE / MARTS) will be wired up via `+schema:`
per folder in `dbt_project.yml` and a `generate_schema_name.sql` macro
that overrides dbt's default schema-concatenation behaviour.

`dbt debug` does not materialize anything — it only checks that dbt can
log in and reach the warehouse — so verifying the connection in this
step is safe with the placeholder schema in place.

### Verifying the connection — `dbt debug`

After loading `.env`, from inside `dbt/`:

```powershell
cd dbt
dbt debug
```

Expected output (key lines):

```
Connection test: [OK connection ok]
All checks passed!
```

If `Connection test: [ERROR ...]` appears, troubleshoot in this order:

1. Re-load `.env` into PowerShell (env vars don't persist across new shells).
2. Confirm the Snowflake warehouse `WH_RETAIL` is reachable (Snowsight →
   Warehouses).
3. Verify credentials by logging into Snowsight with the same user/password
   from `.env`.
4. Check the network — Snowflake free-trial accounts don't typically have IP
   allowlists, but corporate proxies can interfere.

---

## Sections to add as Phase 4 progresses

- `sources.yml` — declares CALENDAR / SELL_PRICES / SALES_TRAIN as
  sources, including freshness checks against `loaded_at`.
- Staging model patterns — file structure, type casting conventions,
  test placement.
- Wide-to-long handling (already pre-pivoted by `pandas.melt` in
  Phase 1; staging just translates `d_NNNN` to real DATEs).
- Warehouse layer — Kimball star schema, surrogate keys via
  `dbt_utils.generate_surrogate_key`, incremental fact build strategy.
- dbt tests — `unique`, `not_null`, relationships, custom singular tests.
- `dbt build` orchestration through Airflow (Phase 4 closeout).

---

## Cross-references

- `EXTRACT_PIPELINE.md` — how data lands in `RETAIL_DB.RAW` (Phase 2/3).
- `PROJECT_PLAN.md` — locked decisions, naming conventions, definition of
  shippable.
- `LEARNINGS.md` — running journal of what was learned during Phase 4.
- `dbt/dbt_project.yml` — the actual project config that this doc
  walks through.
