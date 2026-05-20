# DBT_PIPELINE.md — dbt Transformation Pipeline Walkthrough

> Companion to `EXTRACT_PIPELINE.md`. This doc explains the dbt project that
> transforms RAW Snowflake data into the analytical layers that power Power BI.
>
> Last updated: 2026-05-17 (Phase 4 session 6 closed — Airflow ↔ dbt
> integration via Astronomer Cosmos; `m5_daily_extract` DAG extended from
> 2 tasks to 4 with per-model dbt task generation; failure-injection test
> confirmed clean chain halt at upstream test failure).

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
- `version` — semantic version of _this dbt project_ (not dbt itself).
  Bumped manually when models change shape.
- `config-version: 2` — schema version of this YAML file. Always `2` for
  any modern dbt project. Locked since dbt 0.21.

### Connection profile pointer

```yaml
profile: "retail_demand_forecasting"
```

This is a _reference_. dbt looks for a top-level key called
`retail_demand_forecasting` in `profiles.yml` to find the Snowflake
credentials. `dbt_project.yml` says **what** to do; `profiles.yml` says
**where** to connect.

### Folder paths

```yaml
model-paths: ["models"]
seed-paths: ["seeds"]
test-paths: ["tests"]
analysis-paths: ["analyses"]
macro-paths: ["macros"]
snapshot-paths: ["snapshots"]
```

All six are dbt defaults — listed explicitly so the file shows the whole
shape of a dbt project at a glance. The square brackets are YAML's inline
list syntax; each setting _could_ take multiple folders, but we only use
one each.

| Path             | Folder       | What goes there                                                    |
| ---------------- | ------------ | ------------------------------------------------------------------ |
| `model-paths`    | `models/`    | The actual SELECT statements (`.sql` model files)                  |
| `seed-paths`     | `seeds/`     | Reference CSVs that `dbt seed` loads as small lookup tables        |
| `test-paths`     | `tests/`     | Singular SQL tests — standalone queries that return 0 rows on pass |
| `analysis-paths` | `analyses/`  | Ad-hoc investigative SQL; compiled but not run                     |
| `macro-paths`    | `macros/`    | Reusable Jinja macros — SQL "functions"                            |
| `snapshot-paths` | `snapshots/` | SCD Type 2 snapshot definitions for slowly-changing dimensions     |

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

| Layer        | Materialization                              | Why                                                                                                  |
| ------------ | -------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Staging      | `view`                                       | Cheap, always fresh, no storage cost. Re-runs against RAW on every query.                            |
| Intermediate | `view`                                       | Same reasoning as staging. Light cost, always reflects upstream state.                               |
| Warehouse    | `table` (override `fact_*` to `incremental`) | Dims are small enough to rebuild every run; facts are too large — incremental only inserts new rows. |
| Marts        | `table`                                      | Power BI queries these — needs to be fast. Rebuilt on every dbt run.                                 |

---

## `profiles.yml` — Snowflake connection

dbt finds connection details by looking up the `profile:` key from
`dbt_project.yml` inside `profiles.yml`. The two-file split is deliberate:
`dbt_project.yml` says _what_ to do; `profiles.yml` says _where_ to connect.

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

The shell environment is populated from `.env` _before_ running dbt. This
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

## Per-layer schema separation — `generate_schema_name` macro

By default, dbt concatenates `target.schema` (from `profiles.yml`) with
the per-folder `+schema:` config in `dbt_project.yml`. So if the profile
schema is `RAW` and a model's folder sets `+schema: STAGING`, the model
lands in `RAW_STAGING`. Ugly, and noise for portfolio readers.

The override at `dbt/macros/generate_schema_name.sql` rewrites that
behaviour: if a model's folder declares a `+schema:`, use it directly
without concatenation. Models land in `STAGING`, `INTERMEDIATE`,
`WAREHOUSE`, `MARTS` cleanly.

Wired up by adding `+schema:` per folder in `dbt_project.yml`:

```yaml
models:
  retail_demand_forecasting:
    staging:
      +materialized: view
      +schema: STAGING
    intermediate:
      +materialized: view
      +schema: INTERMEDIATE
    warehouse:
      +materialized: table
      +schema: WAREHOUSE
    marts:
      +materialized: table
      +schema: MARTS
```

Standard pattern in production dbt projects. The override is small
(~8 lines of Jinja) and almost never needs further changes.

---

## `sources.yml` — declaring the M5 source

Lives at `dbt/models/staging/sources.yml`. Declares one source named
`m5` covering the three RAW tables (CALENDAR, SELL_PRICES, SALES_TRAIN).

Three things the file does:

1. **Decoupling.** Every staging model references its raw table via
   `{{ source('m5', 'CALENDAR') }}` instead of hard-coding
   `RETAIL_DB.RAW.CALENDAR`. If the source moves (different schema,
   different database, alias), update one line in `sources.yml` and
   every downstream model still works.

2. **Freshness checks.** Every RAW table has a `LOADED_AT` audit column
   (added by the Phase 2 extract script). `sources.yml` declares this
   field plus warn/error thresholds (36h warn, 72h error). Running
   `dbt source freshness` queries `MAX(LOADED_AT)` from each source
   and surfaces any stale data before downstream models run on it.

3. **Documentation.** Table-level descriptions plus column-level
   descriptions land in `dbt docs generate` output, giving portfolio
   visitors a self-documenting data dictionary.

The `freshness` and `loaded_at_field` keys sit inside a `config:` block
under the source — required syntax from dbt 1.8+ (older flat syntax
deprecated with a `PropertyMovedToConfigDeprecation` warning).

**Verification:**

```powershell
dbt source freshness
```

Returns PASS / WARN / ERROR per source. All three M5 sources passed on
first run after the Phase 3 backfill (LOADED_AT was hours old).

---

## Staging models — three files, two patterns

Staging is the first dbt layer. **Job:** read each RAW table once,
cast types, snake-case columns, drop columns nobody downstream needs.
**Forbidden in strict practice:** joins, business logic, aggregations.

This project bends the strict rule once — `stg_m5_sales_train` joins
to `stg_m5_calendar` to translate the M5 `d_NNNN` day identifier into
a real DATE. The join is fundamentally part of cleaning the source
(every downstream model wants a real DATE), so it sits in staging
rather than intermediate. Locked decision in `PROJECT_PLAN.md`.

### Pattern A — simple SELECT-FROM-source (`stg_m5_sell_prices`)

When the model has one logical step (read, light cleanup), a flat
SELECT is enough. No CTEs.

```sql
SELECT
    store_id,
    item_id,
    wm_yr_wk,
    sell_price
FROM {{ source('m5', 'SELL_PRICES') }}
```

`stg_m5_sell_prices` literally just drops the `loaded_at` audit column.
Source types are already correct (NUMBER(10,4) for price), naming is
already snake_case. The file is 9 lines.

`stg_m5_calendar` is slightly more involved — casts `date` (VARCHAR
in raw) to a real DATE, renames `snap_CA/TX/WI` to lowercase. Still
flat SELECT pattern, ~20 lines.

### Pattern B — CTE chain (`stg_m5_sales_train`)

Once a model does more than one logical step, the dbt style-guide
convention is CTEs. Three (or more) named `WITH` blocks, ending in
`SELECT * FROM <last_cte>`.

```sql
WITH source AS (
    SELECT * FROM {{ source('m5', 'SALES_TRAIN') }}
),

calendar AS (
    SELECT d, calendar_date FROM {{ ref('stg_m5_calendar') }}
),

joined AS (
    SELECT ...
    FROM source s
    LEFT JOIN calendar c ON s.d = c.d
)

SELECT * FROM joined
```

Three benefits:

- Each CTE has one clear job — reads top-to-bottom like a recipe.
- Easy to debug — swap `joined` for `source` in the final SELECT to
  peek at intermediate state without rewriting the model.
- Easy to extend — adding a new transformation step is just another
  CTE in the chain.

Note `{{ ref('stg_m5_calendar') }}` (not `source()`) — the calendar is
another dbt model, not a raw table. dbt uses these `ref()` calls to
build the model dependency DAG automatically.

---

## Tests — schema YAML and the join-sentinel pattern

Tests live next to their models in `_staging__models.yml` (leading
underscore sorts the file to the top of the folder). Each column can
declare `data_tests:` — dbt's built-in `unique` and `not_null` cover
most needs in staging; relationships and compound-key uniqueness
arrive with the `dbt_utils` package later.

Eight tests at the end of step 3, fourteen at the end of step 4:

| Model                | Column          | Tests                      |
| -------------------- | --------------- | -------------------------- |
| `stg_m5_calendar`    | `calendar_date` | `unique`, `not_null`       |
| `stg_m5_calendar`    | `d`             | `unique`, `not_null`       |
| `stg_m5_sell_prices` | `store_id`      | `not_null`                 |
| `stg_m5_sell_prices` | `item_id`       | `not_null`                 |
| `stg_m5_sell_prices` | `wm_yr_wk`      | `not_null`                 |
| `stg_m5_sell_prices` | `sell_price`    | `not_null`                 |
| `stg_m5_sales_train` | `id`            | `not_null`                 |
| `stg_m5_sales_train` | `item_id`       | `not_null`                 |
| `stg_m5_sales_train` | `store_id`      | `not_null`                 |
| `stg_m5_sales_train` | `d`             | `not_null`                 |
| `stg_m5_sales_train` | `sale_date`     | `not_null` ← join sentinel |
| `stg_m5_sales_train` | `units_sold`    | `not_null`                 |

`sell_prices` has no single-column uniqueness — its natural key is the
compound `(store_id, item_id, wm_yr_wk)`. Compound-key uniqueness needs
`dbt_utils.unique_combination_of_columns`; deferred until that package
lands.

**The `sale_date NOT NULL` test is the join sentinel.** `stg_m5_sales_train`
uses LEFT JOIN against the calendar, which produces NULL on any unmatched
`d`. The test catches the NULL and surfaces it as a failure rather than
silently dropping the row. Standard defensive pattern — INNER JOIN would
hide the same problem.

---

## The Snowflake permission boundary — what dbt needs

Phase 2 provisioning gave `RETAIL_ENGINEER` everything to operate inside
`RETAIL_DB.RAW` but not to create new schemas at the database level.
First `dbt build` failed with `Insufficient privileges to operate on
database 'RETAIL_DB'`.

**Fix:** one grant in `sql/snowflake/03_grant_dbt_privileges.sql`:

```sql
GRANT CREATE SCHEMA ON DATABASE RETAIL_DB TO ROLE RETAIL_ENGINEER;
```

Snowflake's ownership model handles the rest — when the role creates
`STAGING`, it becomes the owner, with full privileges inside.

**Diagnostic discipline used:** ran `SHOW GRANTS TO ROLE RETAIL_ENGINEER`
_before_ granting anything, confirmed the gap was a single missing
privilege, granted exactly that, re-ran `SHOW GRANTS` to verify the new
row appeared. Avoided the trap of "throw more grants and hope."

Also folded the same grant into `00_provision_account.sql` so a fresh
setup from this repo gets it from day 1.

---

## End-to-end verification

After step 4, the full pipeline runs end-to-end:

```powershell
cd dbt
dbt build --select staging
```

Output (final block):

```
Done. PASS=17 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=17
```

That's 3 view models materialized in `RETAIL_DB.STAGING` plus 14 data
tests, all green in ~5 seconds (Snowflake handles the 59M-row sales
× calendar join efficiently). The pipeline is now real end-to-end:
Azure SQL → Python extract → Snowflake RAW → dbt → Snowflake STAGING.

Eyeball verification of actual rows in Snowsight confirmed the date
cast, the join (`d_1069` → `2014-01-01`), the SNAP column rename, and
the `units_sold` rename all worked as designed.

---

## Package management — installing `dbt_utils`

dbt has a first-class package system, mirroring `npm` for Node, `pip`
for Python, `cargo` for Rust. Three moving parts that show up in this
project from Phase 4 session 3:

### `packages.yml` — declares dependencies

Lives next to `dbt_project.yml`. One entry per external package:

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.1.1", "<2.0.0"]
```

The version range pins to the **1.x** major (semver — any 1.x release
is API-compatible; a hypothetical 2.0 would be breaking). `dbt deps`
resolves the latest matching version (`1.3.3` at install time).

### `dbt deps` — the install command

```powershell
cd dbt
dbt deps
```

Reads `packages.yml`, downloads matching versions from the dbt Hub
(or Git, for non-hub packages), drops them under `dbt_packages/`.
Idempotent — safe to re-run.

### `package-lock.yml` — auto-generated, committed

`dbt deps` writes `dbt/package-lock.yml` recording the _exact_ version
that resolved (here, `dbt_utils 1.3.3`). Same role as `package-lock.json`
or `Pipfile.lock` — guarantees reproducible installs across machines
and CI even if a 1.3.4 ships tomorrow. **Commit it.**

### `dbt_packages/` — gitignored

The actual installed package code lives under `dbt/dbt_packages/`.
Already covered by `.gitignore` line 78. Same logic as `node_modules/`
— regenerated from `packages.yml` + lockfile via `dbt deps`, never
edited directly.

**What `dbt_utils` gives us.** Compound-key uniqueness tests, surrogate
key generation, `not_empty_string`, pivot helpers, date-spine generation,
many others. Library of community macros that solve problems every dbt
project hits. Maintained by dbt-labs itself, so it's safe and stable.

---

## Compound-key tests via `dbt_utils.unique_combination_of_columns`

`stg_m5_sell_prices` has no single-column unique key — its natural key
is the compound `(store_id, item_id, wm_yr_wk)`. dbt's built-in `unique`
test only handles single columns. `dbt_utils` ships the multi-column
equivalent.

### The dbt 1.10+ `arguments:` syntax

Declared at the **model level** (not under a column), since it's a
property of the row, not any single column:

```yaml
- name: stg_m5_sell_prices
  data_tests:
    - dbt_utils.unique_combination_of_columns:
        arguments:
          combination_of_columns:
            - store_id
            - item_id
            - wm_yr_wk
```

The `arguments:` nesting is required from dbt 1.10. Older syntax
omitted it (`combination_of_columns:` lived directly under the test
name); dbt now emits a `MissingArgumentsPropertyInGenericTestDeprecation`
warning if you write the old form. Same semantics, one extra indent.

### What it compiles to

After `dbt build`, the literal SQL Snowflake ran lives at
`dbt/target/compiled/retail_demand_forecasting/models/staging/_staging__models.yml/dbt_utils_unique_combination_o_<hash>.sql`.
Opening that file shows roughly:

```sql
SELECT
    store_id, item_id, wm_yr_wk
FROM RETAIL_DB.STAGING.STG_M5_SELL_PRICES
GROUP BY store_id, item_id, wm_yr_wk
HAVING COUNT(*) > 1
```

Same elegant contract as every dbt test: **zero rows back = pass, any
rows back = fail and they show you exactly which combinations duplicate.**
Worth reading the compiled SQL once for any new macro — demystifies
what dbt is actually asking Snowflake to do.

---

## Intermediate layer — `int_sales_with_prices` walkthrough

The intermediate layer sits between staging (light passthrough) and
warehouse (the published star schema). **Job: business-logic joins
and derivations.** Think of it as the workshop bench where source-aligned
shapes get assembled into business-aligned shapes before going to the
published star.

`int_sales_with_prices` is the first intermediate model. It joins
daily sales to weekly prices via the calendar bridge and computes
`revenue_amount_usd`. Output: 32,898,710 rows (one per sale row,
LEFT-JOIN preserves all of them), materialised as a view.

### CTE structure — `source → enriched → final` shape

```sql
WITH sales AS (
    SELECT * FROM {{ ref('stg_m5_sales_train') }}
),

prices AS (
    SELECT * FROM {{ ref('stg_m5_sell_prices') }}
),

calendar AS (
    SELECT d, wm_yr_wk FROM {{ ref('stg_m5_calendar') }}
),

sales_with_week AS (
    SELECT
        sales.*,
        calendar.wm_yr_wk
    FROM sales
    LEFT JOIN calendar USING (d)
),

joined AS (
    SELECT
        sales_with_week.id,
        sales_with_week.item_id,
        sales_with_week.store_id,
        sales_with_week.d,
        sales_with_week.sale_date,
        sales_with_week.wm_yr_wk,
        sales_with_week.units_sold,
        prices.sell_price,
        sales_with_week.units_sold * prices.sell_price AS revenue_amount_usd
    FROM sales_with_week
    LEFT JOIN prices
        ON sales_with_week.store_id = prices.store_id
        AND sales_with_week.item_id = prices.item_id
        AND sales_with_week.wm_yr_wk = prices.wm_yr_wk
)

SELECT * FROM joined
```

### What each CTE does

| CTE               | Role                                                                        |
| ----------------- | --------------------------------------------------------------------------- |
| `sales`           | Pull from `stg_m5_sales_train`. One row per (item, store, day).             |
| `prices`          | Pull from `stg_m5_sell_prices`. One row per (store, item, fiscal week).     |
| `calendar`        | Slim projection — just the columns needed for the join (`d` → `wm_yr_wk`).  |
| `sales_with_week` | Attach `wm_yr_wk` to every sale via LEFT JOIN on `d`. Bridge step.          |
| `joined`          | LEFT JOIN to prices, compute `revenue_amount_usd`. The business-logic step. |

### Why two LEFT JOINs

**The sales × calendar join.** Every sale row should match exactly one
calendar row (`d` is the calendar's natural key). LEFT JOIN here is
the safe-default form — INNER would also work since `stg_m5_sales_train`
already enforced the `sale_date NOT NULL` join sentinel back in staging.
Kept as LEFT JOIN for consistency with the next step.

**The sales × prices join.** This is where LEFT JOIN earns its keep.
**34.66% of sales rows have no matching price** — M5 only carries
`sell_prices` rows for actively-stocked items. INNER JOIN would silently
drop 11.4M rows. LEFT JOIN preserves them with NULL price. Verified
that _none_ of those priceless rows have positive units sold (anomaly
check in the verify file) — they're legitimate "product not on shelf"
rows, useful demand signal, intentionally kept.

### NULL semantics — `units_sold * NULL = NULL`

The revenue calculation propagates NULL automatically:

```sql
sales_with_week.units_sold * prices.sell_price AS revenue_amount_usd
```

When `sell_price` is NULL, `units_sold * NULL` returns NULL. This is
**correct** — we don't know the revenue, not zero revenue. Downstream
aggregations need to treat these as "unknown" rather than collapsing
to zero. The column description in `_intermediate__models.yml` calls
this out explicitly. The `not_null` test is deliberately **omitted** on
both `sell_price` and `revenue_amount_usd` — those NULLs are by design.

### Tests on the intermediate model

Schema YAML at `dbt/models/intermediate/_intermediate__models.yml`.
Eight tests total:

| Test                                      | Column(s)                        | Why                                                   |
| ----------------------------------------- | -------------------------------- | ----------------------------------------------------- |
| `dbt_utils.unique_combination_of_columns` | `(store_id, item_id, sale_date)` | Confirms no fan-out from the join.                    |
| `not_null`                                | `id`                             | Sales-side PK component.                              |
| `not_null`                                | `item_id`                        | Sales-side PK component.                              |
| `not_null`                                | `store_id`                       | Sales-side PK component.                              |
| `not_null`                                | `d`                              | Sales-side PK component.                              |
| `not_null`                                | `sale_date`                      | Inherited from staging join sentinel.                 |
| `not_null`                                | `wm_yr_wk`                       | Calendar bridge — NULL here would mean calendar miss. |
| `not_null`                                | `units_sold`                     | Sales fact.                                           |

`dbt build --select int_sales_with_prices` → PASS=9 (1 view + 8 tests).

---

## Warehouse layer + materialization transition

`dim_calendar` is the first warehouse-layer model. Crossing this folder
boundary flips the default materialization from `view` to `table` —
no per-model override needed, just the per-folder config in
`dbt_project.yml`:

```yaml
models:
  retail_demand_forecasting:
    intermediate:
      +materialized: view
    warehouse:
      +materialized: table
```

### View vs table — the economics

| Aspect                | View                                                     | Table                                          |
| --------------------- | -------------------------------------------------------- | ---------------------------------------------- |
| Storage cost          | None — just a saved SELECT                               | Pays per byte stored                           |
| Query cost            | Recomputes the SELECT every query                        | Reads pre-built storage                        |
| Freshness vs upstream | Always reflects current upstream                         | Stale until next `dbt run`                     |
| Best for              | Staging, intermediate (light compute, freshness matters) | Warehouse + marts (read-many, latency matters) |

**Why warehouse defaults to table.** Power BI and downstream consumers
hit these models thousands of times. A view-on-view-on-view stack
would re-compute the entire transformation chain on every query.
Pre-materializing tables once per dbt run is the right trade — pay
storage cost once, save compute on every read.

### What dbt actually issues

For a table-materialized model, `dbt run` sends Snowflake roughly:

```sql
CREATE OR REPLACE TABLE RETAIL_DB.WAREHOUSE.DIM_CALENDAR AS
SELECT ...
FROM ...
```

`CREATE OR REPLACE` makes the rebuild idempotent — old table dropped
atomically, new one swapped in. Compiled SQL lives under
`dbt/target/run/<project>/models/warehouse/dim_calendar.sql` after a
build; worth reading once to see the literal CREATE statement dbt
sends over the wire.

---

## Surrogate keys via `dbt_utils.generate_surrogate_key`

Every warehouse dim gets a surrogate key as its primary key, separate
from whatever natural key the source provided. `dim_calendar` uses
`dbt_utils.generate_surrogate_key`:

```sql
{{ dbt_utils.generate_surrogate_key(['calendar_date']) }} AS date_key
```

### What it compiles to

Roughly `MD5(NVL(calendar_date::VARCHAR, '_dbt_utils_surrogate_key_null_')) AS date_key`.
Output: a stable 32-character hex string. Same input always produces
the same output. The MD5 hash gives us:

- **A single column standing in for the natural key.** No matter what
  the natural key looks like (single column, compound, mixed types),
  the surrogate is one VARCHAR(32).
- **Deterministic.** Re-running the dim from scratch produces identical
  keys for identical rows. Fact tables that already hold `date_key`
  values stay valid.

### Why surrogate keys are worth the Jinja line

1. **Decoupling from upstream natural-key drift.** If the source ever
   renames `calendar_date` to `cal_dt` or changes its type, the dim's
   downstream contract (`date_key`) holds. Only the dim's own surrogate
   expression changes.
2. **SCD-2 readiness.** For Type-2 slowly-changing dimensions (e.g.
   if `dim_item` later tracks category history over time), the same
   natural key needs to appear in multiple dim rows, each with its
   own validity window. Surrogate keys handle this trivially — include
   the validity window in the key columns, every version gets a
   distinct hash.
3. **Multi-column natural keys collapse to one column.** Where a dim's
   natural key is compound, the macro accepts a list:
   `generate_surrogate_key(['store_id', 'item_id', 'wm_yr_wk'])`.
   Output is still one 32-char hex string. Facts join on one column.

### The `{{ }}` Jinja invocation pattern

`{{ dbt_utils.generate_surrogate_key(['calendar_date']) }}` is a Jinja
expression — at compile time, dbt evaluates it and substitutes the
resulting SQL into the model file. The model on disk has the `{{ }}`
expression; the compiled SQL Snowflake sees has the raw `MD5(...)` call.
Same templating mechanism as `{{ ref('...') }}` and `{{ source('...') }}`.

---

## `dim_calendar` walkthrough

First warehouse-layer model. One row per date. Output: 1,079 rows
(more on the row count below).

### Source-truth principle — derive everything from `calendar_date`

M5's source `calendar.csv` already pre-computes `weekday`, `wday`,
`month`, `year`. `dim_calendar` deliberately **ignores** those and
derives its own analytical attributes fresh from `calendar_date`:

```sql
DATE_PART('year', calendar_date)    AS year,
DATE_PART('quarter', calendar_date) AS quarter,
DATE_PART('month', calendar_date)   AS month,
MONTHNAME(calendar_date)            AS month_name,
DATE_PART('day', calendar_date)     AS day_of_month,
DAYOFWEEKISO(calendar_date)         AS day_of_week,
DAYNAME(calendar_date)              AS day_name,
WEEKISO(calendar_date)              AS week_of_year,
```

**Why.** Single source of truth. If M5's `weekday` ever disagrees with
Snowflake's `DAYNAME` for any date, we'd want to know — but more
importantly, _the dim's own values become the canonical reference_.
Downstream analysts pulling from `dim_calendar` aren't accidentally
inheriting M5's particular weekday convention.

### ISO date variants for session-independence

- `DAYOFWEEKISO(calendar_date)` — ISO 8601: Monday = 1, Sunday = 7.
  Fixed by international standard. Unchangeable.
- `WEEKISO(calendar_date)` — ISO 8601 week number. Fixed.
- Plain `DAYOFWEEK` and `WEEK` would respond to Snowflake's session
  `WEEK_START` and `WEEK_OF_YEAR_POLICY` parameters — different
  account, different default, different answer for the same date.
  Not what you want in a published dim.

### `is_weekend` via `DAYNAME` for convention-independence

```sql
CASE
    WHEN DAYNAME(calendar_date) IN ('Sat', 'Sun')
    THEN TRUE
    ELSE FALSE
END AS is_weekend
```

`DAYNAME` returns three-letter English abbreviations regardless of
session locale. A numeric `DAYOFWEEK = 6 OR DAYOFWEEK = 7` check would
break if `WEEK_START` changes. The string-based check is invariant.

### `is_holiday` Boolean roll-up

```sql
CASE
    WHEN event_name_1 IS NOT NULL OR event_name_2 IS NOT NULL
    THEN TRUE
    ELSE FALSE
END AS is_holiday
```

Single-column Boolean derived from M5's two event-name columns. Useful
for downstream marts that need a simple "was this a holiday?" filter
without unpacking the event-name detail. The original `event_name_1`
and `event_name_2` are kept alongside for analysts who want the named
event itself.

**Implicit NULL-vs-empty-string verification.** The eyeball check on
a random Friday with no event returned `is_holiday = FALSE` correctly
— which proves the source values are genuine NULLs, not empty strings.
`'' IS NOT NULL` is TRUE in every SQL dialect; if M5's events were
loaded as empty strings, every non-event day would have flipped to
`is_holiday = TRUE`. Subtle but worth knowing.

### Coverage — the 1,079 rows and the future date-spine

`dim_calendar` currently spans **2011-01-29 to 2014-03-21**, mirroring
what's been extracted to RAW. There are gaps (the planned cutoff was
2014-01-04; 2014-03-21 came from a Phase 2 smoke-test extract).

**In production, `dim_calendar` is typically procedurally generated**
— a continuous spine from some start date (e.g. 2010-01-01) to some
end date (e.g. 2030-12-31), independent of fact coverage. Why: Power
BI's time-series axes assume the dim is continuous. A missing date
shows as a continuous line, not a flat zero — collapsing 14 missing
days into 0 days visually.

Standard pattern uses `dbt_utils.date_spine()` to generate the spine,
then LEFT JOINs source attributes (`event_name_*`, `wm_yr_wk`, SNAP
flags) onto it. **Flagged for Phase 6 polish or Project 3.** Current
shape is correct for M5's known-complete date range; the discipline
rule — _dimensions are independent of fact coverage_ — is captured now
for when the next project needs it.

---

## Per-model verification SQL files

A pattern established in Phase 1 (`01_phase1_load_verification.sql`)
and extended every layer since. Each non-trivial model gets its own
re-runnable verification file under `sql/verify/`. Phase 4 session 3
added two:

- `sql/verify/04_phase4_int_sales_with_prices_verification.sql`
- `sql/verify/05_phase4_dim_calendar_verification.sql`

### The pattern

Each file follows the same shape:

1. **Header comment** explaining what the file verifies and that
   sections are independent.
2. **Numbered sections.** Each section is a single SELECT that
   returns one or more rows of evidence. Section order roughly
   matches "biggest impact / fastest triage first."
3. **A single-row PASS/FAIL rollup** as the final section. CTE-based,
   one CASE per check, one row of `PASS` / `FAIL` / `WARN` strings.
   Eyeball it in two seconds after any `dbt build`.

### How they complement `dbt test`

`dbt test` runs the schema-YAML generic tests (uniqueness, not-null,
compound keys). Build-time assertions. **The verify files cover what
generic tests can't:**

- **Distribution sanity** — is the weekend rate ~28.6% as expected?
  Is the NULL-price rate ~35% as the M5 product-lifecycle reasoning
  predicted, not 99%?
- **Cross-model parity** — does `int_sales_with_prices` row count
  match `stg_m5_sales_train`? (Catches join fan-out and silent drops.)
- **Business-logic anomalies** — are there any rows with
  `units_sold > 0 AND sell_price IS NULL`? (Captures the LEFT-JOIN
  semantic argument as an enforceable check.)
- **Eyeball samples** — five rows on known dates, ten rows showing
  the revenue calc. Quick human verification that the numbers look
  right.

### Why they're durable artefacts

- **Version controlled.** Lives in git, reviewable, re-runnable
  against any future state of the warehouse.
- **Re-runnable on demand.** Snowsight → open file → highlight section
  → run. No dbt invocation needed.
- **Self-documenting.** The section comments explain what each check
  asserts and why. Future-me re-reads and understands the model's
  contract without re-deriving it.
- **Interview-ready evidence.** "How do you validate a dbt model
  past the built-in tests?" → "Per-model SQL file with PASS/FAIL
  rollup. Here's one — `05_phase4_dim_calendar_verification.sql`."

For Phase 4 session 3: `04_...verification.sql` Section 5 returns
PASS / PASS (parity + anomaly). `05_...verification.sql` Section 4
returns PASS / PASS (uniqueness + weekend rate 28.64% inside the
27–30% band).

---

## `dim_item` walkthrough

Second warehouse model. Goal: one row per distinct item, surrogate key,
ready for the fact to FK into.

### Design call: source-side vs string parsing

`PROJECT_CONTEXT.md` originally flagged that `dim_item` would derive
`department` and `category` from the `item_id` string (M5 item_ids look
like `HOBBIES_1_001`). When it came time to build, a check of
`stg_m5_sales_train` showed `dept_id` and `cat_id` already shipped as
their own columns from M5's source CSV.

Chose source-side over string parsing:

```sql
SELECT DISTINCT item_id, dept_id, cat_id FROM {{ ref('stg_m5_sales_train') }}
```

vs the alternative:

```sql
SELECT
    item_id,
    SPLIT_PART(item_id, '_', 1) || '_' || SPLIT_PART(item_id, '_', 2) AS dept_id,
    SPLIT_PART(item_id, '_', 1)                                       AS cat_id
FROM ...
```

The source-side approach: cleaner, no parsing logic to maintain, no risk
of getting the format wrong. **Discipline rule**: prefer source-truth
over derivation when the data already has the columns.

### Shape: two CTEs (no `enriched` middle CTE)

`dim_calendar` had a `source → enriched → final` three-CTE shape because
it derived 10+ new columns. `dim_item` has nothing to derive — every
column comes through unchanged from staging. Dropped the middle CTE:

```sql
WITH source AS (
    SELECT DISTINCT item_id, dept_id, cat_id
    FROM {{ ref('stg_m5_sales_train') }}
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['item_id']) }} AS item_key,
        item_id, dept_id, cat_id
    FROM source
)

SELECT * FROM final
```

CTE structure should reflect what the model is doing, not pattern-match
a previous model. Two-CTE for derivation-free dims; three-CTE for dims
that compute attributes.

### Tests + verification

6 tests in `_warehouse__models.yml`: `unique` + `not_null` on both
`item_key` and `item_id`, `not_null` on `dept_id` and `cat_id`.

`sql/verify/06_phase4_dim_item_verification.sql` covers row count + key
uniqueness (expects 3,049 = 3,049 = 3,049), hierarchy cardinality (3
categories, 7 departments — M5 invariants), 5-row attribute eyeball,
single-row PASS/FAIL rollup.

Materialised: 3,049 rows as a table in `RETAIL_DB.WAREHOUSE.DIM_ITEM`.

---

## `dim_store` walkthrough

Smallest dim in the project: 10 rows. Same shape as `dim_item`, same
source-side-not-parsing decision (M5 ships `state_id` as its own column,
so no need to parse `store_id` strings).

```sql
WITH source AS (
    SELECT DISTINCT store_id, state_id
    FROM {{ ref('stg_m5_sales_train') }}
),

final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['store_id']) }} AS store_key,
        store_id, state_id
    FROM source
)

SELECT * FROM final
```

5 tests, all passing.

`sql/verify/07_phase4_dim_store_verification.sql` covers row count + key
uniqueness (expects 10), state distribution (CA=4, TX=3, WI=3 — M5
invariants), full-table eyeball (10 rows fits, no LIMIT), single-row
PASS/FAIL rollup.

Materialised: 10 rows as a table in `RETAIL_DB.WAREHOUSE.DIM_STORE`.

---

## `fact_daily_sales` walkthrough — the centrepiece

The first fact table in the project, the first incremental model, the
first model with Snowflake clustering. Grain: **one row per item ×
store × day**. Full load: ~32.9M rows. Source: `int_sales_with_prices`.

### Materialization config

```sql
{{ config(
    materialized='incremental',
    unique_key='sale_key',
    cluster_by=['sale_date'],
    on_schema_change='fail'
) }}
```

**`materialized='incremental'`** — first build is a full load;
subsequent builds only process rows the `is_incremental()` block lets
through. Saves re-processing 32.9M rows every time dbt runs.

**`unique_key='sale_key'`** — together with Snowflake's default
`incremental_strategy='merge'`, dbt does an UPSERT against the existing
table: rows with a `sale_key` already in the table get UPDATEd; new
`sale_key`s INSERT. Safe even if a re-run overlaps a date that's
already been processed.

**`cluster_by=['sale_date']`** — Snowflake clustering. See "Snowflake
clustering" subsection below.

**`on_schema_change='fail'`** — defensive default. If a future change
adds or renames a column, dbt errors instead of silently truncating
data. Explicit beats implicit on a fact table you care about.

### The `is_incremental()` Jinja guard

```sql
WITH source AS (
    SELECT
        item_id, store_id, sale_date,
        units_sold, sell_price, revenue_amount_usd
    FROM {{ ref('int_sales_with_prices') }}

    {% if is_incremental() %}
        WHERE sale_date > (
            SELECT COALESCE(MAX(sale_date), '1900-01-01')
            FROM {{ this }}
        )
    {% endif %}
),
```

`is_incremental()` returns FALSE on the first build (target table
doesn't exist yet) → the WHERE block is skipped → full historical load.
Returns TRUE on every subsequent build → only rows with a newer
`sale_date` than the current table's max enter.

The `COALESCE(MAX(sale_date), '1900-01-01')` handles the edge case of
"table exists but is empty" — without it, `MAX()` of an empty table is
NULL, and `WHERE sale_date > NULL` evaluates to UNKNOWN (effectively
FALSE) on every row → no rows would enter. The COALESCE backstops it.

### Snowflake clustering — the BigQuery-partition equivalent

Snowflake doesn't have explicit partitions like BigQuery
(`PARTITION BY sale_date`). It has **automatic micro-partitions**
(50–500MB compressed slices that Snowflake manages internally) and an
optional **clustering key** that tells Snowflake how to physically
co-locate rows when re-organising those micro-partitions in the
background.

`cluster_by=['sale_date']` on the fact is the equivalent of partitioning
on `sale_date`: tells Snowflake to keep rows with adjacent `sale_date`
values in the same micro-partitions. Date-range queries (the dominant
access pattern for a fact table — "show me sales for last week") then
prune micro-partitions and scan less data.

Clustering happens automatically in background re-organising. No
maintenance commands needed.

### Compute-same-way FK keys (no JOIN to dims)

The fact has four surrogate keys:

```sql
final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['item_id', 'store_id', 'sale_date']) }} AS sale_key,
        {{ dbt_utils.generate_surrogate_key(['item_id']) }}                          AS item_key,
        {{ dbt_utils.generate_surrogate_key(['store_id']) }}                         AS store_key,
        {{ dbt_utils.generate_surrogate_key(['sale_date']) }}                        AS date_key,
        item_id, store_id, sale_date,
        units_sold, sell_price, revenue_amount_usd
    FROM source
)
```

`item_key` here is `MD5(item_id)`. `dim_item.item_key` is also
`MD5(item_id)`. Same input → same output, deterministically. FK-PK
matching is by construction — no need to JOIN-and-lookup `dim_item` at
build time to resolve the key.

**Trade-off**: this approach can't enforce "every fact `item_key`
corresponds to a row in `dim_item`" at build time the way a JOIN would
have. That's what the `relationships` tests catch. See next subsection.

### `relationships` tests at scale

Three FK `relationships` tests in `_warehouse__models.yml`:

```yaml
- name: item_key
  data_tests:
    - relationships:
        arguments:
          to: ref('dim_item')
          field: item_key
```

(and analogous for `store_key` → `dim_store`, `date_key` → `dim_calendar`.)

Each test runs a `WHERE NOT EXISTS` query: "any fact rows whose FK
doesn't exist in the dim?" Expected count: zero.

**Performance**: each test completed in **<0.5 seconds** on the full
32.9M-row fact. Snowflake resolves them as hash joins with the dim's PK
in memory (dims are 1k–3k rows, fits in a single XS warehouse slot).
The instinct from row-store databases is "relationships tests on large
facts are slow" — on Snowflake (or any columnar warehouse with a
half-decent optimiser) they're cheap.

### `accepted_range` test for measure constraints

Codified `units_sold >= 0` as a column-level test:

```yaml
- name: units_sold
  data_tests:
    - not_null
    - dbt_utils.accepted_range:
        arguments:
          min_value: 0
          inclusive: true
```

`dbt_utils.accepted_range` is dbt-idiomatic for "this column's values
are within a range." Cleaner test output than the equivalent
`dbt_utils.expression_is_true` with `expression: 'units_sold >= 0'`.
`inclusive: true` makes the boundary unambiguous (0 itself is allowed —
zero-unit rows are legitimate "product on shelf, didn't sell" demand
signal).

### Compound-key uniqueness — the grain enforcer

```yaml
data_tests:
  - dbt_utils.unique_combination_of_columns:
      arguments:
        combination_of_columns:
          - item_id
          - store_id
          - sale_date
```

Plus the surrogate `sale_key` has `unique` + `not_null` tests directly.

Two layers of grain enforcement: the natural-key combination
(`item_id`, `store_id`, `sale_date`) is unique, and the surrogate
`sale_key` (which is `MD5(item_id, store_id, sale_date)`) is unique.
Either alone would catch a grain violation; both together catch any
drift between natural-key uniqueness and surrogate-key computation.

### Modern `arguments:` syntax — dbt 1.10+ deprecation lesson, second hit

The first build raised
`MissingArgumentsPropertyInGenericTestDeprecation` three times — once
per `relationships` test. Same deprecation we caught in session 3 on
the compound-key test. Fix is identical: wrap the test arguments in an
`arguments:` block:

```yaml
# Old (deprecated):
- relationships:
    to: ref('dim_item')
    field: item_key

# Modern (dbt 1.10+):
- relationships:
    arguments:
      to: ref('dim_item')
      field: item_key
```

**Discipline rule reinforced after two hits**: every new generic test
(any test whose name has a `.` like `dbt_utils.*`, or the built-in
`relationships`) needs the modern `arguments:` wrapping from the start.
Treat the deprecation as if it were an error — fix it on first write,
not after the deprecation warning surfaces.

### Build outcome

First targeted build (`dbt build --select fact_daily_sales`):
**32,898,710 rows materialised + 12 tests passing in 21.97 seconds**.

Subsequent full-DAG `dbt build --no-partial-parse`: **15.26 seconds**
end-to-end across the whole project (1 incremental + 3 tables + 4 views

- 58 tests). The incremental's `is_incremental()` evaluated to "no new
  dates beyond 2014-03-21" → MERGE found zero new rows → near-instant
  re-validation. The three dims re-materialised fully (table
  materialisations drop + recreate) but they're 3k / 10 / 1k rows. Views
  are query definitions, not materialisations. Tests dominate the runtime
  budget.

### Verification

`sql/verify/08_phase4_fact_daily_sales_verification.sql` covers 6
sections:

1. Row-count parity with upstream `int_sales_with_prices` (32.9M = 32.9M)
2. `sale_key` uniqueness across all 32.9M rows
3. FK referential integrity — counts of orphan FKs against each dim (all zero)
4. Sale-date coverage + measure sanity (date range, min/max units_sold, NULL-price rate, total revenue)
5. Five-row eyeball with INNER JOIN to all three dims — proves the star schema is wired end-to-end
6. Single-row PASS/FAIL rollup

**Total revenue across the dataset: $93,559,341.40 USD.** Real number
from a real pipeline — worth carrying as scale-of-data signal for
interview talk-track.

---

## Phase-boundary structural audit applied to the dbt layer

At the close of Phase 4 session 4, a structural pass across the dbt
project + verify file folder caught two issues that would otherwise
have been frozen into the session commit:

1. **`04_` filename collision** —
   `04_phase4_int_sales_with_prices_verification.sql` (session 3) shared
   a numeric prefix with `04_phase4_staging_layer_verification.sql` (session
   2). Renamed the intermediate one to `04a_` to preserve monotonic
   ordering without renumbering downstream `05_` / `06_` / `07_` /
   `08_` files.
2. **Stale `.gitkeep` placeholders** — `staging/`, `intermediate/`, and
   `warehouse/` model folders still had the session-1 scaffolding
   placeholders despite now containing real models. Removed. Only
   `marts/.gitkeep` remains pending session 5.

Both were 30-second fixes once caught. The audit principle is documented
in `CODE_QUALITY.md` → "Phase-boundary structural audit"; this was its
first explicit application.

---

## `mart_executive_overview` walkthrough

> **Historical note (added 2026-05-20).** This section reflects the model
> as originally built in Phase 4 session 5. In Phase 5 session 5.3 the
> model was renamed to `agg_sales_daily` with structural changes (added a
> surrogate `date_key` FK to `dim_calendar`; dropped the natural-key
> `sale_date` column) to support being a Power BI user-defined aggregation
> candidate. A second aggregate `agg_sales_daily_item_cat` (day × cat_id
> rollup) was added at the same time. In Phase 5 session 5.4 the UDA plan
> was found architecturally incompatible with all-Import models (UDA
> requires DirectQuery on the Detail Table per Microsoft Learn); both agg
> tables remain in dbt + Snowflake as portfolio narrative artefacts but
> are NOT wired into Power BI. The walkthrough below is preserved as a
> teaching artefact showing the original lean-marts pattern; current PBI
> state is documented in `POWERBI_PLAYBOOK.md` and `PROJECT_CONTEXT.md`.

First (and currently only) model in the marts layer. Grain: one row per
`sale_date`. Source: `WAREHOUSE.fact_daily_sales`. Output: 1,079 rows
materialised as a table in `RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW`.
Downstream consumer: the Power BI dashboard's home page.

The mart is the lean-marts pattern's first concrete artefact in this
project. The original Phase 4 plan was five marts (one per Power BI page);
the direction changed at session 5 open in favour of exposing the warehouse
star (`fact_daily_sales` + the three dims) directly to Power BI and using
marts only for pre-aggregations that earn their keep. Full reasoning lives
in `LEARNINGS.md` → "2026-05-17 — Lean marts layer + analyst-facing star
schema". This walkthrough covers the resulting build.

### The lean-marts call in one paragraph

Marts exist when they earn their keep — pre-aggregation for performance,
or cross-domain joins that don't belong in any single fact. The dashboard
home page hits a daily summary thousands of times across user sessions;
pre-aggregating once at dbt build and reading 1,079 rows from Power BI is
dramatically cheaper than re-aggregating 32.9M rows per query. The other
Power BI pages (Demand by Hierarchy, Seasonality & Calendar, Promotion &
Price, Forecast vs Actual) take their data straight from the warehouse
star — sliced and diced inside Power BI's own VertiPaq engine. Same
architectural pattern modern analyst-facing teams ship in real shops.

### Shape — two-CTE source → aggregated

```sql
{{ config(
    materialized='table'
) }}

WITH source AS (
    SELECT *
    FROM {{ ref('fact_daily_sales') }}
),

aggregated AS (
    SELECT
        sale_date,
        SUM(units_sold)                                              AS total_units_sold,
        SUM(revenue_amount_usd)                                      AS total_revenue_usd,
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN item_id  END)   AS active_item_count,
        COUNT(DISTINCT CASE WHEN units_sold > 0 THEN store_id END)   AS active_store_count
    FROM source
    GROUP BY sale_date
)

SELECT * FROM aggregated
```

Materialised as a table per `dbt_project.yml`'s marts-folder default.
Power BI reads this repeatedly so the table must be fast; the storage
cost (1,079 rows × 5 columns) is trivial and well-spent. No `incremental`
config: at 1,079 rows a full rebuild is single-digit seconds, and a
daily-summary mart has no clean incremental key (every fact-row change
for an existing date should update that date's mart row — a full table
rebuild handles this cleanly; `merge` semantics are overkill).

The `source` CTE pulls the upstream fact unchanged — same naming
convention as every other model in this project. Makes "swap the source"
a one-line edit later if the upstream is ever renamed or refactored.

### Two SQL idioms worth a deep look

**`SUM` with NULL-containing measures.** ANSI `SUM()` ignores NULLs by
default. `revenue_amount_usd` is NULL on ~34.66% of fact rows (M5
product-lifecycle — items without an active price for that fiscal week),
so `SUM(revenue_amount_usd)` skips those rows and totals only the priced
ones. This is the right semantic: a row with unknown revenue contributing
zero beats a row defaulted to `0` and silently understating the day's
revenue. Power BI sees daily revenue numbers that represent what was
actually transacted with a known price; analysts answering "why doesn't
revenue / units = average price reconcile?" can point at this column's
NULL rate as the explanation.

**`CASE`-inside-`COUNT(DISTINCT ...)`.** Classic SQL idiom for "count
distinct things matching a condition." The `CASE` emits the id only when
`units_sold > 0` (NULL otherwise); `COUNT(DISTINCT ...)` skips NULLs.
Result: a count of items and stores that actually sold something that
day, excluding the on-shelf-didn't-sell rows that legitimately exist in
the fact (preserved as a demand signal but counted as "inactive" for
executive-dashboard purposes). Cleaner and cheaper than the subquery
alternative `(SELECT COUNT(DISTINCT item_id) FROM ... WHERE units_sold > 0)`
because Snowflake can resolve it in a single pass.

### Test design at the mart layer

Ten tests in `_marts__models.yml`:

| Column               | Tests                                  |
| -------------------- | -------------------------------------- |
| `sale_date`          | `unique` + `not_null` (PK enforcement) |
| `total_units_sold`   | `not_null` + `accepted_range >= 0`     |
| `total_revenue_usd`  | `not_null` + `accepted_range >= 0`     |
| `active_item_count`  | `not_null` + `accepted_range 0..3049`  |
| `active_store_count` | `not_null` + `accepted_range 0..10`    |

Two design calls worth flagging.

**`not_null` on `total_revenue_usd`** — even though the underlying
`revenue_amount_usd` is nullable at the fact level. The reasoning:
nullability at the fact is correct (M5 product-lifecycle gaps are real),
but at the aggregate level a NULL daily total would mean every row in
that day's fact has NULL price — a catastrophic upstream condition.
Codifying `not_null` here turns "an entire day's pricing is missing"
into a test failure rather than a silent blank cell in Power BI.

**`accepted_range` upper bounds tied to dim cardinalities.** `max_value:
3049` is the total distinct item count in M5; `max_value: 10` is the
total distinct store count. These caps make a category of grain bug
(accidental cross-join, key explosion, fan-out from a botched join)
machine-detectable rather than human-spotted. If either test ever fires,
something upstream is fanning out the fact's grain — not a downstream
display bug.

### Build outcome + aggregation compression

Targeted build (`dbt build --select mart_executive_overview`): **PASS=11
in 7.56 seconds** (1 model + 10 tests). Full-DAG rebuild after shipping
the mart (`dbt build --no-partial-parse`): **PASS=78 in 17.72 seconds**
end-to-end (1 incremental + 4 tables + 4 views + 69 tests). The
incremental fact's `is_incremental()` block evaluates to "no new dates
beyond 2014-03-21" → MERGE finds zero rows → near-instant; the three
dims rebuild their ~3k / 10 / 1k rows quickly; the new mart adds 1,079
rows of work plus its 10 tests.

**Aggregation compression: 32,898,710 → 1,079 rows = ~30,500× reduction.**
Power BI reads 1,079 rows instead of 33M. A material change to home-page
refresh time and the storage that lives in Power BI's in-memory model.
Worth carrying for the interview talk-track: _"I pre-aggregated 32.9M
fact rows down to a 1,079-row daily summary, a ~30,500× compression that
makes the dashboard home page instant in Power BI."_

### Verification

`sql/verify/09_phase4_mart_executive_overview_verification.sql` —
durable verification artefact, 6 numbered sections + single-row PASS/FAIL
rollup. Follows the same pattern as `05_` through `08_`.

| Section | What it asserts                                                                                                                                                              |
| ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1       | Upstream parity: mart's `SUM(total_units_sold)` and `SUM(total_revenue_usd)` equal the fact's corresponding aggregates; mart's `COUNT(DISTINCT sale_date)` equals the fact's |
| 2       | PK uniqueness: `COUNT(*)` = `COUNT(DISTINCT sale_date)` (Snowsight-side re-confirmation of the dbt test)                                                                     |
| 3       | Active counts reconcile: re-compute the `CASE`-inside-`COUNT(DISTINCT)` values from the fact for one sample date (2013-06-15) and confirm parity                             |
| 4       | Headline measure sanity: full-mart totals + date range + row count, verifying $93,559,341.40 total revenue carries through                                                   |
| 5       | Five-row eyeball: five evenly-spaced dates with all measures, see-it-yourself check                                                                                          |
| 6       | Single-row PASS/FAIL rollup: 4-column health check across `units_parity` / `revenue_parity` / `pk_unique` / `active_store_max`                                               |

First-run results (session 5): §1 → 3 rows of mart = fact parity (units
34,437,817; revenue $93,559,341.40; date_count 1,079); §2 → 1,079 = 1,079
with 0 duplicates; §3 → mart 2,205/10 = fact 2,205/10 on 2013-06-15; §4 →
$93,559,341.40 confirmed; §5 → five rows all positive, `active_store_count`
= 10 on every sampled date; **§6 → 4× PASS**.

---

## Airflow orchestration of dbt — Astronomer Cosmos integration

Phase 4 session 6 extended the existing `m5_daily_extract` Airflow DAG so
that dbt runs automatically after each successful daily extract. Each dbt
model becomes its own Airflow task with full per-model lineage in the
Airflow UI, via the Astronomer Cosmos provider package. This section walks
through what Cosmos is, why it was chosen, and exactly how the integration
sits across the Dockerfile, the docker-compose volume mounts, and the DAG
file itself.

### What Cosmos does (and why not BashOperator or hand-wiring)

Cosmos is an Airflow provider that reads a dbt project's manifest at
DAG-parse time and **generates one Airflow task per dbt model + one per
dbt test**, with dependencies mirrored from dbt's own `ref()` graph. The
result: the Airflow UI's Graph view shows the dbt DAG directly, and a
single failing model surfaces in Airflow as a single red task square with
a link to its dbt logs.

Three alternatives were considered:

1. **Defer dbt orchestration to Project #3.** Cheaper in the near term but
   leaves the headline DE deliverable (_end-to-end orchestrated pipeline_)
   only half-built. Rejected.
2. **One `BashOperator` that shells out to `dbt build`.** Simplest possible.
   One opaque task fires green or red with no per-model visibility — if a
   model breaks, you can't tell which one from the Airflow UI; you have to
   open the logs and read the dbt output. Functional but doesn't impress.
3. **Hand-wire one `BashOperator` per dbt model.** Workable but maintains
   the model list in two places (dbt project + Airflow DAG). Every new
   model, rename, or rewire requires updating both. Two sources of truth
   that have to be kept in sync.

Cosmos wins on the third axis specifically: **automation plus single source
of truth**. The dbt project is the only place where models and their
dependencies are declared; Cosmos regenerates the Airflow tasks at every
DAG-parse cycle. Add a new dbt model, restart Airflow, the new task appears.

For the targeted role-shape (BI Analyst / DE-adjacent in Melbourne), Cosmos
is also the integration approach real shops use in 2025-26 — showing it in
a portfolio repo signals current-tooling fluency.

### The four-task chain — DAG anatomy

Before session 6, `m5_daily_extract` had 2 tasks:

```
extract_one_day → verify_one_day
```

After session 6, the same DAG has 4 stages:

```
extract_one_day → verify_one_day → [dbt_models task group] → verify_dbt_one_day
```

| Task                 | Purpose                                                            | Pattern                                                                         |
| -------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| `extract_one_day`    | Pull one day's M5 slice from Azure SQL into `RETAIL_DB.RAW`        | Existing @task; wraps `scripts/extract_azure_to_snowflake.py`                   |
| `verify_one_day`     | Cross-check Snowflake-side that the extract landed                 | Existing @task; 3 row-count checks in one round-trip                            |
| `dbt_models`         | Run all 9 dbt models + 9 model-level test tasks                    | New: Cosmos `DbtTaskGroup` (auto-generated)                                     |
| `verify_dbt_one_day` | Cross-check Snowflake-side that the dbt build populated all layers | New @task; 9 row-count checks across STAGING / INTERMEDIATE / WAREHOUSE / MARTS |

Each task uses Airflow's default `trigger_rule="all_success"`, so the chain
halts cleanly on the first failure — a broken dbt test sets `dbt_models`
to red and `verify_dbt_one_day` to `upstream_failed` (never executes). The
overall DAG run is marked failed.

### Three pieces of installation surface

Cosmos is wired into the running Airflow stack via three changes — one to
the Python image's pip layer, one to the Dockerfile's structure, and one
to docker-compose's volume mounts.

**1. `astronomer-cosmos` itself goes into the main Airflow venv.**
A single line added to `airflow/requirements-airflow.txt`:

```
astronomer-cosmos>=1.7,<2.0
```

The range pin is a departure from the file's existing no-pin convention
(documented in the comment above the line). Cosmos has independent semver
and ships breaking changes between major versions; without a pin, a future
`2.0.0` release would silently land in the image on rebuild and could
break the DAG. Same range-pin shape `dbt/packages.yml` uses for
`dbt_utils`.

**2. dbt-snowflake gets its own isolated venv inside the image.**
A new stage at the bottom of `airflow/Dockerfile`:

```dockerfile
RUN python -m venv /opt/airflow/dbt_venv \
    && /opt/airflow/dbt_venv/bin/pip install --no-cache-dir \
       dbt-core==1.11.10 dbt-snowflake==1.11.5
```

Why a separate venv: dbt's pinned shared dependencies (`jinja2`, `pyyaml`,
etc.) conflict with Airflow's constraints file. Installing dbt in the
main env would either fail the build or silently downgrade something
Airflow needs. Astronomer's documented recommendation. Cosmos shells out
to `/opt/airflow/dbt_venv/bin/dbt` via `ExecutionConfig(dbt_executable_path=...)`
at DAG-time.

**3. The dbt project becomes visible to the worker via a bind mount.**
A single line added to `airflow/docker-compose.yml` under the shared
`x-airflow-common.volumes`:

```yaml
- ../dbt:/opt/airflow/dbt:ro
```

`:ro` (read-only) because nothing inside the container should ever
rewrite the dbt models — those are version-controlled on the host. Same
pattern as the existing `../scripts:/opt/airflow/scripts:ro` mount from
Phase 3. The mount sits inside the shared YAML anchor, so all three
Airflow services (init, webserver, scheduler) automatically see it.

### Cosmos config block — ProjectConfig, ProfileConfig, ExecutionConfig

The four config primitives live at module level in `airflow/dags/m5_daily_extract.py`,
declared once and reused inside the DAG function:

```python
DBT_PROJECT_PATH = "/opt/airflow/dbt"
DBT_EXECUTABLE_PATH = "/opt/airflow/dbt_venv/bin/dbt"

project_config = ProjectConfig(DBT_PROJECT_PATH)
profile_config = ProfileConfig(
    profile_name="retail_demand_forecasting",
    target_name="dev",
    profiles_yml_filepath=f"{DBT_PROJECT_PATH}/profiles.yml",
)
execution_config = ExecutionConfig(
    dbt_executable_path=DBT_EXECUTABLE_PATH,
)
```

- **`ProjectConfig`** — tells Cosmos _where_ the dbt project lives on disk.
- **`ProfileConfig`** — tells Cosmos _how_ to authenticate. Two flavours:
  Airflow connection translation (the "real shop" pattern) or pointing at
  the existing `profiles.yml`. This project uses the latter so both
  execution environments (manual PowerShell `dbt build` + Airflow runs)
  share the same `env_var()` → `.env` resolution path. One credential
  surface, two execution paths.
- **`ExecutionConfig`** — tells Cosmos _which_ dbt binary to invoke. Points
  at the isolated venv from the Dockerfile.

The `profile_name="retail_demand_forecasting"` and `target_name="dev"`
strings must match exactly what's in `dbt/profiles.yml` (top-level key
and the `target:` value respectively). Mismatch → Cosmos fails to
authenticate at parse-time.

### The `DbtTaskGroup` instantiation — 13 lines that replace 150

Inside the `@dag` function, after the existing `extract_one_day` and
`verify_one_day` @task definitions:

```python
dbt_models = DbtTaskGroup(
    group_id="dbt_models",
    project_config=project_config,
    profile_config=profile_config,
    execution_config=execution_config,
    default_args={"retries": 2},
)

extract_one_day() >> verify_one_day() >> dbt_models >> verify_dbt_one_day()
```

These 13 lines (the `DbtTaskGroup` instantiation + the wiring) replace
what would otherwise be:

- 9 `BashOperator` task definitions, one per dbt model (~80 lines)
- 9 more `BashOperator` task definitions for `dbt test --select <model>` (~80 lines)
- All the `>>` dependency wiring between them, mirroring `ref()` calls (~15 lines)
- A maintenance burden of keeping all of that in sync with the dbt project by hand

So: ~150 lines of brittle, hand-maintained Airflow code → 13 lines of
Cosmos config that regenerates from dbt's own truth on every DAG-parse.

### Cosmos's default `test_behavior=AFTER_EACH`

The Airflow Graph view, when `dbt_models` is expanded, shows each dbt
model as a tiny sub-TaskGroup containing two sub-tasks:

- A `run` task (instance of `DbtRunLocalOperator`) — shells out to
  `dbt run --select <model_name>`
- A `test` task (instance of `DbtTestLocalOperator`) — shells out to
  `dbt test --select <model_name>` immediately after the model builds

This is Cosmos's default `test_behavior=AFTER_EACH`: each model's tests
fire immediately after that model itself succeeds, halting dependent
models cleanly on test failure. The alternatives (`AFTER_ALL` — all
models run first, then all tests as a separate group; `BUILD` — combine
run + test into a single `dbt build --select <model>` task) are both
configurable via `RenderConfig`, but `AFTER_EACH` is the right default
for our case: it stops a downstream model from building on top of
upstream data that just failed validation.

The task count math: 9 dbt models × 2 Airflow tasks each = **18
auto-generated tasks** inside the `dbt_models` group. The 78 dbt test
_assertions_ (the YAML `unique` + `not_null` + `accepted_range` +
`relationships` checks across all layers) all run inside the 9
model-level `test` tasks, with each task running its model's assertions
sequentially and reporting pass/fail at the model level. Cleaner UI than
78 individual test squares would have been.

### Import paths — the lazy-imports workaround

The natural import statement at the top of the DAG file:

```python
from cosmos import DbtTaskGroup, ProjectConfig, ProfileConfig, ExecutionConfig
```

…compiled and ran cleanly in the Airflow worker but triggered Pylance
errors (`Object of type object is not callable. Attribute __call__ is
unknown`) in the local IDE. The cause: Cosmos's `cosmos/__init__.py`
uses **lazy imports via `__getattr__`** for memory-saving reasons —
the names `DbtTaskGroup`, `ProjectConfig`, etc. aren't statically present
in the `cosmos` namespace at static-analysis time; they're loaded
dynamically on first access. Pylance can't follow that pattern and
degrades the unknown names to bare `object`, producing the "not
callable" diagnostic.

Workaround: import each class from its actual submodule path:

```python
from cosmos.airflow.task_group import DbtTaskGroup
from cosmos.config import ExecutionConfig, ProfileConfig, ProjectConfig
```

Runtime behaviour is identical (Python loads the same classes either
way), but Pylance can statically resolve the submodule paths. Clean
diagnostics, zero suppression comments.

### dbt-core and adapter version pinning — the 1.8+ decoupling

First install attempt pinned both dbt-core and dbt-snowflake to `1.11.5`
to match the project's local `.venv`. Build failed with `pip
ResolutionImpossible`:

```
The user requested dbt-core==1.11.5
dbt-snowflake 1.11.5 depends on dbt-core<2.0 and >=1.11.6
```

Since the dbt 1.8 release, dbt-core and the adapters (`dbt-snowflake`,
`dbt-postgres`, etc.) have **independent patch release cycles**. The
two version numbers don't need to match — and in this case the adapter
explicitly requires a higher patch than its own version number.

Fix: pin both exactly, but to different patches:

```dockerfile
RUN python -m venv /opt/airflow/dbt_venv \
    && /opt/airflow/dbt_venv/bin/pip install --no-cache-dir \
       dbt-core==1.11.10 dbt-snowflake==1.11.5
```

`dbt-core==1.11.10` is the latest patch in the 1.11.x line and is the
version pip resolved to on its own when only `dbt-snowflake==1.11.5` was
pinned. The local `.venv` was already on the same pair (pip resolved
identically when installed), so no local sync required. Documented in
the Dockerfile comment above the line so a future engineer reading the
repo understands why the numbers diverge.

### Airflow data_interval semantics — `logical_date` vs `ds`

A subtle gotcha that fired during the end-to-end trigger test. Airflow
2.x distinguishes:

- `logical_date` (formerly `execution_date`): the timestamp the run is
  scheduled at — for an `@daily` schedule, this is the END of the data
  interval (or the start of the NEXT interval).
- `data_interval_start`: the start of the data period the run is
  supposed to process.
- `ds` template: `data_interval_start` formatted as `YYYY-MM-DD`.

For a DAG with `@daily` schedule and start_date in Melbourne tz:

- Trigger `logical_date = 2014-03-22 00:00:00 Melbourne` (= 2014-03-21
  13:00 UTC).
- → `data_interval_start = 2014-03-21 00:00 Melbourne`
- → `context["ds"] = "2014-03-21"`
- The extract pulls Azure SQL data for **2014-03-21**, not for 2014-03-22.

Carry-forward: when manually triggering a date X, set logical_date to
**X + 1 day** to actually process X. The Airflow trigger form's "Logical
Date" field is one interval ahead of the data being processed. Cosmetic
but easy to miss; bit us once in this session.

### `verify_dbt_one_day` — Snowflake-side validation of the dbt build

Mirrors the existing `verify_one_day` pattern but checks the dbt output
layers rather than the RAW extract. Nine row-count checks batched into a
single SELECT (one warehouse round-trip):

| Layer        | Check                                                | Bound  |
| ------------ | ---------------------------------------------------- | ------ |
| STAGING      | `stg_m5_calendar` rows for `run_date`                | `== 1` |
| STAGING      | `stg_m5_sell_prices` joined to calendar via wm_yr_wk | `> 0`  |
| STAGING      | `stg_m5_sales_train` rows for `run_date`             | `> 0`  |
| INTERMEDIATE | `int_sales_with_prices` rows for `run_date`          | `> 0`  |
| WAREHOUSE    | `dim_calendar` full-table row count                  | `> 0`  |
| WAREHOUSE    | `dim_item` full-table row count                      | `> 0`  |
| WAREHOUSE    | `dim_store` full-table row count                     | `> 0`  |
| WAREHOUSE    | `fact_daily_sales` rows for `run_date`               | `> 0`  |

> The MARTS-layer row check on `mart_executive_overview` was removed in
> Phase 5 session 5.4 when the table was renamed to `agg_sales_daily` with
> a structural change (sale_date → date_key surrogate). The fact-layer
> check above already validates that dbt's incremental MERGE landed the
> day's data; downstream agg/mart layer derives from fact, so a separate
> per-run mart check is redundant.

Any failure aggregates into a single `RuntimeError` message that names
every failing layer + observed vs expected counts — actionable diagnosis
without grepping logs. Same `failures.append(...)` pattern as
`verify_one_day`.

### Incremental fact backfill — the gotcha caught at trigger time

The first end-to-end manual trigger (logical_date 2014-01-05) failed at
`verify_dbt_one_day` with `WAREHOUSE.FACT_DAILY_SALES: expected > 0 rows
for 2014-01-04, got 0` and the corresponding mart check failing too. The
fact's existing `MAX(sale_date)` was `2014-03-21` (from the session 4
build); the incremental WHERE clause `sale_date > MAX(sale_date)` filtered
out `2014-01-04` (and any other date inside the existing range).

The fix for the test trigger was to pick a date **after** the current
fact max — `logical_date = 2014-03-23` → `ds = 2014-03-22` → fact's
incremental filter passes the new date through to MERGE.

The broader lesson is structural: `WHERE sale_date > MAX(sale_date)`
patterns only **extend forward**; they cannot **backfill** historical
dates within their existing range. For backfill use cases the answer is
`dbt run --full-refresh` (rebuilds the whole fact from scratch). Worth
flagging because the demo-time use of "trigger any historical date" runs
into this; the @daily-forward use of the same DAG (extract today, add to
fact tomorrow) does not.

### Failure injection test — confirming the chain halts cleanly

Closing validation of the four-task chain: flipped the mart's
`active_store_count` `accepted_range` from `max_value: 10` to
`max_value: 5` in `dbt/models/marts/_marts__models.yml`, triggered a fresh
manual run, observed the exact behaviour predicted:

- `extract_one_day` → green
- `verify_one_day` → green
- `dbt_models` task group → all 9 model `run` tasks green, all 8 upstream
  model `test` tasks green, then `mart_executive_overview.test` → **red**
  (the broken `accepted_range` test fired against the rebuilt mart and
  failed across essentially every row). Task group status: red overall.
- `verify_dbt_one_day` → **upstream_failed** (state, not failed). Duration
  `00:00:00`. Trigger rule `all_success` evaluated to "not all upstream
  succeeded," so the task was marked upstream_failed and never executed.
- Overall DAG run → failed.

Reverted the YAML edit after the test; the project state is clean and
the success path (Sept 22) was previously proven green end-to-end. The
test demonstrates the chain halts at the dbt test failure cleanly,
without firing the downstream verify task on broken data.

### Build outcomes + interview talk-track

**Headline numbers** (all from this session's end-to-end trigger for
`2014-03-22`):

- DAG run duration: **5:31** end-to-end (extract + verify + 9 dbt models
  × 2 tasks each + verify_dbt = 21 tasks total)
- All 21 task squares green; verify_dbt_one_day's 9 layer checks all pass
- Cosmos's per-model lineage visible in the Airflow Graph view
- Failure-injection test produced clean upstream_failed propagation

**Interview talk-track:**

> "I integrated dbt and Airflow via Astronomer Cosmos. Cosmos parses the
> dbt manifest at DAG-parse time and creates one Airflow task per dbt
> model + per test — so the Airflow lineage graph shows the dbt model DAG
> directly, and a failure on a single model surfaces in the Airflow UI as
> a single red task with a link to its dbt logs. Cleaner observability
> than wrapping `dbt build` in a single BashOperator. I also wired a
> downstream `verify_dbt_one_day` task that runs nine row-count checks
> across the dbt output layers, so we catch silent failures inside the
> pipeline rather than in a Power BI dashboard the next morning."

### File-change summary (Phase 4 session 6)

| File                               | Change                                                                                                                                               |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| `airflow/requirements-airflow.txt` | Added `astronomer-cosmos>=1.7,<2.0`                                                                                                                  |
| `airflow/Dockerfile`               | New `RUN` stage creates `/opt/airflow/dbt_venv` and installs `dbt-core==1.11.10 + dbt-snowflake==1.11.5`                                             |
| `airflow/docker-compose.yml`       | Added `../dbt:/opt/airflow/dbt:ro` volume mount                                                                                                      |
| `airflow/dags/m5_daily_extract.py` | Cosmos imports + module-level config block + `DbtTaskGroup` + `verify_dbt_one_day` @task + wiring update; pre-existing `fetchone()` None-guard added |

The dbt project itself was unchanged — Cosmos reads it as-is.

---

## Cross-references

- `EXTRACT_PIPELINE.md` — how data lands in `RETAIL_DB.RAW` (Phase 2/3).
- `PROJECT_PLAN.md` — locked decisions, naming conventions, definition of
  shippable.
- `LEARNINGS.md` — running journal of what was learned during Phase 4.
- `dbt/dbt_project.yml` — the actual project config that this doc
  walks through.
