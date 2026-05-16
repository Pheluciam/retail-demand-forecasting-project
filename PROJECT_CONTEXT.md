# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Live state of the project. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-16 (Phase 4 session 4 closed — warehouse layer complete: dim_item + dim_store + first incremental fact `fact_daily_sales` (32.9M rows, $93.5M total revenue), 24 new tests, full DAG green in 15.26s. CODE_QUALITY.md gained a new "Phase-boundary structural audit" section — applied immediately and caught two real findings (`04_` filename collision + stale `.gitkeep` placeholders), both fixed in-session before commit. 12 new LEARNINGS entries; 4 new DBT_PIPELINE walkthrough sections).

---

## Where we are right now

**Current phase:** **Phase 4 session 4 ✅ DONE** — warehouse layer complete. `dim_item` (3,049 rows, 6 tests) and `dim_store` (10 rows, 5 tests) shipped using the two-CTE source-side pattern (no string parsing — M5 ships `dept_id`/`cat_id`/`state_id` as their own columns in staging, so chose direct passthrough over `SPLIT_PART` regex). `fact_daily_sales` shipped as the project's first **incremental** model and first model with Snowflake clustering — 32,898,710 rows materialised in 21.97s with 13 tests (including 3 FK `relationships`, 1 compound-key uniqueness, 1 `dbt_utils.accepted_range` for `units_sold >= 0`); subsequent full-DAG `dbt build --no-partial-parse` rebuilt the whole project in **15.26 seconds** (incremental's `is_incremental()` block evaluated to "no new dates beyond 2014-03-21" → MERGE found zero rows → near-instant). Four surrogate keys (`sale_key`, `item_key`, `store_key`, `date_key`) all via `dbt_utils.generate_surrogate_key`; compute-same-way matching to the three dims (same MD5 input → same hash → FK-PK matching by construction, no JOIN-to-dim needed). `relationships` tests on the 32.9M-row fact each completed in **<0.5s** — counter to the row-store intuition that relationships tests scale poorly. **`MissingArgumentsPropertyInGenericTestDeprecation` re-encountered** (3 occurrences on the new `relationships` tests) — same dbt 1.10+ lesson from session 3, fixed by wrapping arguments in `arguments:` block; discipline rule now reinforced after the second hit. **New framework principle captured: Phase-boundary structural audit** added to `CODE_QUALITY.md` between "Three additional failsafes" and "Why this checklist exists" — a structural pass over file inventory at every phase boundary, before docs closeout and before the bundled commit. First explicit application caught two real findings: `04_` filename collision in `sql/verify/` (renamed `04_phase4_int_sales_with_prices_verification.sql` → `04a_` to preserve monotonic ordering without renumbering downstream `05_`-`08_` files) and three stale `.gitkeep` placeholders in `staging/`/`intermediate/`/`warehouse/` model folders (deleted; only `marts/.gitkeep` remains pending session 5). Both 30-second fixes in-session; both would have been frozen into the session commit otherwise. **Portfolio scale captured for interview talk-track**: 32.9M fact rows, $93,559,341.40 total revenue, 3,049 items × 10 stores × ~1,148 days, 0 orphan FKs across three relationships tests, 58 dbt tests across the project, 15.26s full DAG re-validation. 12 new LEARNINGS entries appended to the dbt section (phase-boundary audit headline, incremental materialization, Snowflake clustering vs BigQuery partitioning, compute-same-way keys vs JOIN-to-dims, relationships at scale, `accepted_range`, deprecation re-encounter, `dim_item` design call, two-CTE pattern, MD5 surrogate consistency across the star, first full-DAG rebuild timing, headline numbers). DBT_PIPELINE.md +4 walkthrough sections (`dim_item`, `dim_store`, `fact_daily_sales` deep-dive, structural audit applied to dbt). The dbt project now spans `RAW → STAGING → INTERMEDIATE → WAREHOUSE` end-to-end with full test coverage; only MARTS remains. Next session opens **Phase 4 session 5** — the marts layer (one mart per Power BI page).

**Last action (2026-05-16 — Phase 4 session 4):** Closed the warehouse layer end-to-end. Three new models shipped: `dim_item` (3,049 rows, 6 tests, two-CTE source-side pattern), `dim_store` (10 rows, 5 tests, identical shape), `fact_daily_sales` (32,898,710 rows as the project's first **incremental** model with `unique_key='sale_key'`, `cluster_by=['sale_date']`, `on_schema_change='fail'`, 13 tests including three FK `relationships`, compound-key uniqueness, and `accepted_range` on `units_sold`). First targeted build of the fact: 21.97s for 32.9M rows + 12 tests. Subsequent full-DAG `dbt build --no-partial-parse`: **15.26s** end-to-end (PASS=66 / WARN=0 / ERROR=0). The incremental's `is_incremental()` block evaluated to "no new dates beyond 2014-03-21" → MERGE found zero new rows → near-instant rebuild. Three `relationships` tests on the 32.9M-row fact each completed in <0.5s — Snowflake's optimiser resolves them as hash joins with the small dims in memory. The compute-same-way FK-key pattern (re-hash `item_id`/`store_id`/`sale_date` on the fact side via `dbt_utils.generate_surrogate_key`, same inputs as the dims' PKs → matching hashes by construction) avoided the cost of three JOINs against the 32.9M-row fact at build time, with `relationships` tests catching any drift. **`MissingArgumentsPropertyInGenericTestDeprecation` re-encountered** — 3 occurrences on the new `relationships` tests in `_warehouse__models.yml`. Same dbt 1.10+ lesson from session 3 on the compound-key test; fix is identical (wrap args in `arguments:` block). Second hit reinforces the discipline rule: every new generic test gets modern `arguments:` syntax from the start. **Polish-add caught in the 10-point audit**: empirical `MIN(units_sold) = 0` confirmed in verify Section 4, but no codified test — added `dbt_utils.accepted_range` with `min_value: 0, inclusive: true` so the constraint is machine-enforced not just human-spotted. **`dim_item` design call worth remembering**: `PROJECT_CONTEXT` had originally flagged "derive department/category from item_id structure" — when it came time to build, staging already had `dept_id`/`cat_id` as separate columns shipped from M5's CSV. Chose `SELECT DISTINCT item_id, dept_id, cat_id` over `SPLIT_PART` regex. Discipline rule: prefer source-truth over derivation when the data already has the columns; "derive from structure" is the fallback, not the default. **New framework principle: phase-boundary structural audit** added to `CODE_QUALITY.md` between "Three additional failsafes" and "Why this checklist exists". Distinct from the per-script 10-point audit — verifies the project as a *collection* is consistent (no naming collisions, no stale scaffolding, no missing pairings, no test-count drift). First explicit application caught two real findings: (a) `04_phase4_int_sales_with_prices_verification.sql` (session 3) shared a numeric prefix with `04_phase4_staging_layer_verification.sql` (session 2) — renamed the intermediate one to `04a_` to preserve monotonic ordering without renumbering downstream `05_`/`06_`/`07_`/`08_` files; (b) three stale `.gitkeep` placeholders in `staging/`/`intermediate/`/`warehouse/` model folders despite those folders now containing real models — deleted; only `marts/.gitkeep` remains pending session 5. Both 30-second fixes in-session; both would have been frozen into the session commit otherwise. The audit paid for itself on its first run.

**Files added this session (Phase 4 session 4):**

- `dbt/models/warehouse/dim_item.sql` — second warehouse dim. Two-CTE shape (source DISTINCT → final with surrogate). `{{ dbt_utils.generate_surrogate_key(['item_id']) }}` for `item_key` (32-char MD5 hex). 3,049 rows materialised as table in `RETAIL_DB.WAREHOUSE.DIM_ITEM`. 6 tests passing.
- `dbt/models/warehouse/dim_store.sql` — third warehouse dim. Same two-CTE shape. `state_id` passthrough from staging — no `SPLIT_PART` on `store_id`. 10 rows materialised as table. 5 tests passing.
- `dbt/models/warehouse/fact_daily_sales.sql` — first fact + first incremental model. `materialized='incremental'`, `unique_key='sale_key'`, `cluster_by=['sale_date']`, `on_schema_change='fail'`. `is_incremental()` Jinja guard on `sale_date` with `COALESCE` backstop for "table exists but empty" edge case. Four surrogate keys via `generate_surrogate_key` — `sale_key` (compound `item_id`+`store_id`+`sale_date`), `item_key` (`item_id`), `store_key` (`store_id`), `date_key` (`sale_date`). 32,898,710 rows materialised in 21.97s. 13 tests passing.
- `sql/verify/06_phase4_dim_item_verification.sql` — durable verification artefact for `dim_item`. 4 numbered sections (uniqueness + row count; hierarchy cardinality; 5-row attribute eyeball; PASS/FAIL rollup).
- `sql/verify/07_phase4_dim_store_verification.sql` — for `dim_store`. 4 sections (uniqueness + row count; state distribution; full-table eyeball; PASS/FAIL rollup).
- `sql/verify/08_phase4_fact_daily_sales_verification.sql` — for `fact_daily_sales`. 6 sections (upstream parity; surrogate-key uniqueness on 32.9M rows; FK referential integrity against all three dims; sale-date coverage + measure sanity including $93.5M total revenue check; 5-row eyeball with INNER JOIN across all three dims; PASS/FAIL rollup).

**Files updated this session (Phase 4 session 4):**

- `dbt/models/warehouse/_warehouse__models.yml` — added three new model entries covering 24 new tests total. Fact entry includes model-level compound-key test via `dbt_utils.unique_combination_of_columns`, surrogate `sale_key` uniqueness, three `relationships` FK tests against the dims, `dbt_utils.accepted_range` on `units_sold`, and `not_null` on every natural-key/grain/measure column. All generic tests use modern dbt 1.10+ `arguments:` syntax (caught and fixed the 3 deprecation occurrences mid-session).
- `CODE_QUALITY.md` — added new section "Phase-boundary structural audit" between "Three additional failsafes" and "Why this checklist exists". ~50 lines. Documents the principle, the why, the what-to-check table, when to run, how to run, and the first explicit application (this session). Footer last-updated date bumped.
- `LEARNINGS.md` — appended 12 new dbt-section entries: phase-boundary structural audit (headline meta-lesson), incremental materialization, Snowflake clustering vs BigQuery partitioning, compute-same-way FK keys vs JOIN-to-dims, relationships test performance at scale, `accepted_range` vs `expression_is_true`, the deprecation re-encounter, `dim_item` design call, two-CTE pattern, MD5 surrogate consistency across the star, first full-DAG rebuild timing, headline portfolio numbers.
- `DBT_PIPELINE.md` — header date bumped + 4 new walkthrough sections inserted before "Sections to add as Phase 4 progresses": `dim_item` walkthrough (source-side-vs-parsing decision + two-CTE shape), `dim_store` walkthrough (identical shape, smallest dim), `fact_daily_sales` deep-dive (materialization config, `is_incremental()` Jinja guard, Snowflake clustering, compute-same-way keys, relationships at scale, `accepted_range`, compound-key uniqueness, modern `arguments:` syntax, build outcome, verification), and "Phase-boundary structural audit applied to the dbt layer" (cross-references CODE_QUALITY.md, documents the two findings). The "Sections to add" placeholder trimmed to just Marts + Orchestration. File now ~1,300+ lines.
- `sql/verify/04_phase4_int_sales_with_prices_verification.sql` → renamed to `04a_phase4_int_sales_with_prices_verification.sql` to resolve the `04_` prefix collision with the session-2 staging verify file. Preserves monotonic ordering without renumbering the downstream `05_`/`06_`/`07_`/`08_` files.
- `dbt/models/staging/.gitkeep`, `dbt/models/intermediate/.gitkeep`, `dbt/models/warehouse/.gitkeep` — deleted. Stale scaffolding from Phase 4 session 1; folders now contain real models. Only `dbt/models/marts/.gitkeep` remains pending session 5.
- `PROJECT_CONTEXT.md` — this file. Top of file updated (header "Last updated" + "Current phase" paragraph + this new session 4 block).

**Headline outcomes from this session (Phase 4 session 4):**

- **Warehouse layer complete.** All three dims + the fact built, tested, and verified. The dbt project now spans `RAW → STAGING → INTERMEDIATE → WAREHOUSE` end-to-end with full test coverage; only MARTS remains. From a "shape of the pipeline" perspective, the analytical model is feature-complete.
- **First incremental model in the project.** `fact_daily_sales` introduces `is_incremental()`, `unique_key`, MERGE strategy, and Snowflake clustering all at once. First targeted build: 21.97s for 32.9M rows + 12 tests. Subsequent full-DAG rebuild: 15.26s end-to-end. Strong interview talk-track — "end-to-end retail star schema with 32.9M-row fact, 58 tests, full DAG re-validation in 15 seconds."
- **`relationships` tests are cheap on Snowflake.** Three FK tests on a 32.9M-row fact each completed in <0.5 seconds. Counter to the row-store intuition that "relationships tests on large facts are slow" — Snowflake's optimiser resolves them as hash joins with the small dims (1k–3k rows) held in memory. The cost-effective enforcement layer for the compute-same-way FK pattern.
- **New framework principle captured: phase-boundary structural audit.** Added to `CODE_QUALITY.md` as a check distinct from the per-script 10-point audit. First application caught two real issues (`04_` filename collision, stale `.gitkeep` files) that would otherwise have been frozen into the session commit. Discipline rule for every future phase boundary — staging in Project 3, lakehouse layers, marts, etc.
- **Deprecation re-encountered, lesson reinforced.** `MissingArgumentsPropertyInGenericTestDeprecation` fired three times on the new `relationships` tests. Same lesson from session 3 — second hit. The deprecation is now baked in as a discipline rule: every new generic test (any test name with a `.` or the built-in `relationships`) gets modern `arguments:` wrapping from the start, not after the deprecation warning surfaces.
- **Portfolio scale captured.** 32,898,710 fact rows, $93,559,341.40 total revenue, 3,049 items × 10 stores × ~1,148 days of coverage, 0 orphan FKs, 58 dbt tests, 15.26s full-DAG re-validation. Real numbers from a real pipeline — kind of scale-of-data signal that elevates a portfolio repo from "I followed a tutorial" to "I built and validated a production-shaped pipeline."

**Next session (Phase 4 session 5):**

1. Marts layer — one pre-aggregated mart per Power BI page (5 marts total): Executive Overview, Demand by Hierarchy, Promotion & Price, Seasonality & Calendar, Forecast vs Actual. Pre-aggregated for fast dashboard refresh and explicit lineage between BI and warehouse.
2. `mart_*` materialisation defaults to `table` per `dbt_project.yml`. Consider `incremental` on any mart whose aggregation logic is amenable (probably only Forecast vs Actual will need it; the others should fit comfortably in single-digit-second full rebuilds).
3. Schema YAML + tests on each mart — `unique` + `not_null` on PK at minimum; `accepted_range` on key measures where business rules exist.
4. Per-model verify SQL files (`09_` / `10_` / `11_` / `12_` / `13_phase4_*_verification.sql`).
5. Delete `dbt/models/marts/.gitkeep` once the first mart lands.
6. End-of-phase structural audit + 10-point code-quality audit + doc updates + bundled commit. Closes Phase 4.

---

**Last action (2026-05-16 — Phase 4 session 3):** Opened the intermediate and warehouse layers in one session. `dbt_utils 1.3.3` installed via `packages.yml` + `dbt deps`; `package-lock.yml` auto-generated and committed; `dbt_packages/` already gitignored on line 78. Compound-key uniqueness test added to `stg_m5_sell_prices` for `(store_id, item_id, wm_yr_wk)` — first use of `dbt_utils.unique_combination_of_columns`. Caught dbt 1.10+ deprecation mid-session — `MissingArgumentsPropertyInGenericTestDeprecation` on the new test — fixed by wrapping macro args in `arguments:` (modern syntax); re-ran with `--no-partial-parse` to flush the deprecation cache. Built `int_sales_with_prices` (intermediate, view) using `source → enriched → final` CTE pattern: LEFT JOIN to `stg_m5_calendar` to attach `wm_yr_wk`, LEFT JOIN to `stg_m5_sell_prices` for `sell_price`, computed `revenue_amount_usd = units_sold * sell_price`. Live-verified in Snowsight via three checks (row-count parity 32.9M = 32.9M, 10-row sample with row-level revenue math all spot-on, NULL-price rate 34.66% — explained by M5 product lifecycle). 8 tests pass on the model. Built `dim_calendar` (warehouse, **table**) using the same CTE pattern with `{{ dbt_utils.generate_surrogate_key(['calendar_date']) }}` for `date_key` (32-char MD5 hex). All date attributes derived fresh from `calendar_date` via Snowflake ISO date variants (`DAYOFWEEKISO`, `WEEKISO`) for session-parameter independence; `is_weekend` via `DAYNAME(...) IN ('Sat', 'Sun')` for convention-independence; `is_holiday` Boolean rolls up `event_name_1 IS NOT NULL OR event_name_2 IS NOT NULL`. 1,079 rows, 11 tests pass. Verified live in Snowsight via two checks (key uniqueness + row count + date range, 5-row attribute eyeball on three known holidays + one weekend + one ordinary weekday); third "distribution sanity" check added to the verify file confirmed weekend rate 28.64% (vs theoretical 28.57%), holiday rate 8.16%, 30 distinct event names (broader than first guess of ~14). NULL-vs-empty-string trap caught implicitly — `is_holiday = FALSE` on event-less rows proves event columns are genuine NULLs not empty strings (an empty string would have flipped the flag TRUE — classic SQL gotcha). 10-point code-quality audit: 8 ✅ initially, 2 ⚠️ resolved in-session (anomaly check + verify SQL files); final state 10 ✅, 0 ⚠️, sqlfluff still deferred to Phase 6 per plan. Anomaly check (`units_sold > 0 AND sell_price IS NULL`) returned 0 rows — proves the LEFT JOIN didn't silently drop real sales; every priceless row is a zero-units row, validating LEFT JOIN as a semantic design choice (preserves "product on shelf, didn't sell" demand signal that INNER would have lost). Two per-model verification SQL files created — `04_phase4_int_sales_with_prices_verification.sql` (5 sections + Section 5 rollup), `05_phase4_dim_calendar_verification.sql` (4 sections + Section 4 rollup). Spun up a parallel sub-agent partway through the dbt work to build `GLOSSARY.md` — ~155 terms across 16 sections (~880 lines, `[Project 2]` tags on project-specific entries so general terms lift cleanly into Project 3). Strong portfolio polish move at low marginal cost. Mid-session refinement to `TEACHING_PREFERENCES.md`: Snowsight diagnostic queries follow the same one-query-per-code-block rule as PowerShell (Phil's preference, captured for carry-forward).

**Files added this session (Phase 4 session 3):**

- `dbt/packages.yml` — declares `dbt-labs/dbt_utils` with range pin `>=1.1.1, <2.0.0`. Short header points at `DBT_PIPELINE.md` walkthrough.
- `dbt/package-lock.yml` — auto-generated by `dbt deps`. Pins resolved version `1.3.3` for reproducibility. Commit it (dbt-community convention).
- `dbt/models/intermediate/int_sales_with_prices.sql` — first intermediate model. ~50 lines. `source → enriched → joined` CTE pattern; LEFT JOIN to calendar then prices; revenue computed in final SELECT; clean professional version with short header.
- `dbt/models/intermediate/_intermediate__models.yml` — schema yml. 1 model-level compound-key test + 7 column-level not_null tests. Deliberate omission of not_null on `sell_price` / `revenue_amount_usd` (legitimately NULL by design; documented in column descriptions).
- `dbt/models/warehouse/dim_calendar.sql` — first warehouse model. ~70 lines. CTE pattern. `{{ dbt_utils.generate_surrogate_key(['calendar_date']) }}` for `date_key`. ISO date variants throughout. Materialises as table per `dbt_project.yml` warehouse default.
- `dbt/models/warehouse/_warehouse__models.yml` — schema yml. 2 PK contracts (unique + not_null on `date_key` and `calendar_date`) + 7 not_null on engineered flags / join keys / SNAP columns. 11 tests total. Deliberate omission of not_null on by-construction-non-null derived columns (anti-gold-plating per CODE_QUALITY.md).
- `sql/verify/04_phase4_int_sales_with_prices_verification.sql` — durable verification artefact for the intermediate model. 5 numbered sections (parity, NULL-price rate, anomaly check, 10-row eyeball, PASS/FAIL rollup). Re-runnable from Snowsight any time.
- `sql/verify/05_phase4_dim_calendar_verification.sql` — durable verification artefact for the warehouse dim. 4 numbered sections (uniqueness + row count + date range, 5-row attribute eyeball, distribution sanity, PASS/FAIL rollup).
- `GLOSSARY.md` — project-root glossary. ~155 terms across 16 sections (~880 lines). Project-2-specific entries tagged `[Project 2]` so the general data engineering terms lift cleanly into Project 3 and beyond. Built by a parallel sub-agent during the dbt work.

**Files updated this session (Phase 4 session 3):**

- `dbt/models/staging/_staging__models.yml` — added model-level `dbt_utils.unique_combination_of_columns` test on `stg_m5_sell_prices` for `(store_id, item_id, wm_yr_wk)`. Uses modern dbt 1.10+ `arguments:` syntax (caught and fixed the `MissingArgumentsPropertyInGenericTestDeprecation` mid-session). Test count goes 14 → 15 on the staging layer.
- `LEARNINGS.md` — appended 12 new dbt-section entries (parallel sub-agent): `dbt_utils` install + lockfile, `arguments:` syntax, what "parsing" means in dbt, the rows-back-equals-failures contract for tests, compound keys (Harding's Hardware analogy), intermediate layer purpose, LEFT JOIN as semantic choice, materialization transition view → table, surrogate keys via `generate_surrogate_key`, ISO date variants, NULL-vs-empty-string trap, date-spine pattern future-improvement. File grew from ~535 to ~1,003 lines.
- `DBT_PIPELINE.md` — added 7 new sections (parallel sub-agent): package management, compound-key tests, intermediate layer walkthrough, warehouse + materialization transition, surrogate keys, `dim_calendar` walkthrough, per-model verification SQL files. File grew from ~535 to ~1,007 lines. Header "Last updated" bumped to 2026-05-16.
- `TEACHING_PREFERENCES.md` — added one new bullet in the "Anything else Claude should know" section: Snowsight diagnostic queries follow the same one-query-per-code-block rule as PowerShell. Captured Phil's preference for running each diagnostic separately so Snowsight's history view stays readable.
- `PROJECT_CONTEXT.md` — this file. Top of file updated (header date + "Current phase" paragraph + this new session 3 block).

**Headline outcomes from this session (Phase 4 session 3):**

- **Two new dbt layers live in one session.** Intermediate and warehouse both opened. The dbt project now spans `RAW → STAGING → INTERMEDIATE → WAREHOUSE` end-to-end; only `MARTS` remains. From a "shape of the pipeline" perspective, the project is now real.
- **Three reusable patterns shipped that repeat across every future model.** (a) Compound-key uniqueness tests via `dbt_utils.unique_combination_of_columns` with modern `arguments:` syntax, (b) MD5 surrogate keys via `dbt_utils.generate_surrogate_key` (works for single-column and compound natural keys identically), (c) per-model verification SQL files with numbered sections + single-row PASS/FAIL rollups.
- **Anomaly check earned its keep on first use.** Confirming 0 rows with `units_sold > 0 AND sell_price IS NULL` upgraded the LEFT JOIN decision from "safe choice" to "right choice with documented justification." Preserves "product on shelf didn't sell" rows as legitimate demand signal — INNER JOIN would have silently dropped 11.4M of those rows.
- **NULL-vs-empty-string trap caught implicitly.** Strong real example for interview talk track — `is_holiday = FALSE` on event-less rows proved the underlying values were genuine NULLs (an empty string would have flipped the flag TRUE; `'' IS NOT NULL` evaluates to TRUE in every major SQL dialect).
- **Documentation step-changed.** `GLOSSARY.md` is the standout bonus — uncommon for portfolio repos, clean signal to recruiters that vocabulary is being built deliberately. `LEARNINGS.md` and `DBT_PIPELINE.md` got 12 + 7 substantive new entries respectively, both close to doubling in size. Both will support job-interview deep-dives.

**Next session (Phase 4 session 4):**

1. `dim_item` — second dimension table. `item_key` surrogate via `dbt_utils.generate_surrogate_key(['item_id'])`. Adds `department` / `category` derived from item_id structure (M5 item_ids are `<DEPT>_<CAT>_<NNN>`). ~3,049 rows.
2. `dim_store` — third dimension. Smallest of the three (~10 rows). `store_key` surrogate. Derived `state` from store_id structure (M5 store_ids are `<STATE>_<NN>`).
3. `fact_daily_sales` — the centrepiece. Materialised as `incremental` table partitioned on `sale_date`. Sources from `int_sales_with_prices`; layers on dim foreign keys (`item_key`, `store_key`, `date_key`). The first model where incremental semantics matter and the first model where partitioning is real.
4. Run `dbt build` end-to-end across the whole DAG; capture timings as a benchmark.
5. Per-model verify SQL files for the three new models (`06_`, `07_`, `08_phase4_*_verification.sql`).
6. 10-point code-quality audit + doc updates + bundled commit.

---

**Last action (2026-05-15 afternoon — Phase 4 session 2):** Built the staging layer end-to-end. Per-layer schema separation wired up (custom `generate_schema_name` macro + `+schema:` per folder in `dbt_project.yml`) — clean schema names (STAGING, INTERMEDIATE, WAREHOUSE, MARTS) instead of dbt's default concatenation gotcha. `sources.yml` shipped with column docs + 36h/72h freshness thresholds (all three sources PASS on `dbt source freshness`); fixed a dbt 1.11 `PropertyMovedToConfigDeprecation` warning by nesting `loaded_at_field` + `freshness` under `config:`. Three staging models written: `stg_m5_calendar` (flat SELECT — cast date to DATE, snake-case SNAP columns), `stg_m5_sell_prices` (9-line passthrough), `stg_m5_sales_train` (CTE pattern with LEFT JOIN to `stg_m5_calendar` for `d_NNNN` → real DATE translation). 14 data tests in `_staging__models.yml` including the `sale_date NOT NULL` join sentinel. **Real bug caught mid-session:** first `dbt build --select staging` failed with Snowflake `Insufficient privileges to operate on database 'RETAIL_DB'` — the role didn't have `CREATE SCHEMA` on `RETAIL_DB`. Diagnosed with `SHOW GRANTS`, fixed with new `sql/snowflake/03_grant_dbt_privileges.sql` (single GRANT), re-ran successfully. 10-point audit applied at close: 8 ✅, 1 ⚠️ flagged for Phase 6 (sqlfluff), 1 ⚠️ closed in-session (eyeball SELECTs in Snowsight). Final state: `dbt build --select staging` → PASS=17 (3 views + 14 tests) in 4.5 seconds.

**Files added this session (Phase 4 session 2):**

- `dbt/macros/generate_schema_name.sql` — 8-line Jinja macro overriding dbt's default schema-name concatenation. Models land in clean schemas (STAGING / INTERMEDIATE / WAREHOUSE / MARTS) instead of `RAW_STAGING` etc. Header comment explains the why; full walkthrough in `DBT_PIPELINE.md`.
- `dbt/models/staging/sources.yml` — declares the three RAW tables as the `m5` source. ~95 lines, mostly column documentation. Includes `config:` block with `loaded_at_field: LOADED_AT` and freshness thresholds (36h warn / 72h error). All three sources PASS on `dbt source freshness`.
- `dbt/models/staging/stg_m5_calendar.sql` — staging view, ~20 lines. Casts `date` VARCHAR → DATE (renamed to `calendar_date` to avoid the SQL reserved word). Snake-cases SNAP flags. Materialises to `STAGING.STG_M5_CALENDAR`.
- `dbt/models/staging/stg_m5_sell_prices.sql` — staging view, 9 lines. Pure passthrough minus `loaded_at`. Materialises to `STAGING.STG_M5_SELL_PRICES`.
- `dbt/models/staging/stg_m5_sales_train.sql` — staging view, ~40 lines using the dbt-style-guide CTE pattern (source → calendar → joined). LEFT JOIN against `{{ ref('stg_m5_calendar') }}` to translate `d_NNNN` → real `sale_date`. Renames `sales` → `units_sold` for unambiguous meaning. Materialises to `STAGING.STG_M5_SALES_TRAIN`.
- `dbt/models/staging/_staging__models.yml` — schema YAML documenting all three staging models + 14 `data_tests:` (2 `unique` + 12 `not_null`). The `sale_date NOT NULL` test is the calendar-join sentinel.
- `sql/snowflake/03_grant_dbt_privileges.sql` — single `GRANT CREATE SCHEMA ON DATABASE RETAIL_DB TO ROLE RETAIL_ENGINEER`. Idempotent, includes `SHOW GRANTS` verification block. Created to fix the permission-boundary gap discovered mid-session.

**Files updated this session (Phase 4 session 2):**

- `dbt/dbt_project.yml` — added `+schema: STAGING / INTERMEDIATE / WAREHOUSE / MARTS` lines under each folder in the `models:` block. Four new lines total.
- `sql/snowflake/00_provision_account.sql` — added `GRANT CREATE SCHEMA ON DATABASE RETAIL_DB TO ROLE RETAIL_ENGINEER` to the Phase 2 grant section so future fresh setups from this repo don't repeat the Phase 4 gap.
- `LEARNINGS.md` — appended 8 new dbt-section entries: the grant-fix gap (headline, full root-cause/fix/discipline/carry-forward shape), Snowflake ownership model + interview line, `ref()` vs `source()`, the CTE staging pattern, LEFT-JOIN-as-sentinel, schema YAML naming convention, `dbt build` vs `run` vs `test`, and the dbt 1.11 freshness-config deprecation.
- `DBT_PIPELINE.md` — six new sections: per-layer schema separation walkthrough, `sources.yml` declaration + freshness, staging Pattern A (flat) vs Pattern B (CTE) with a tests table, the join-sentinel pattern, the Snowflake permission boundary fix, and end-to-end verification block.
- `PROJECT_CONTEXT.md` — this file, session 2 closeout.

**Headline outcomes from this session (Phase 4 session 2):**

- **Staging layer live end-to-end.** 3 view models materialised in `RETAIL_DB.STAGING`, 14 data tests passing. Pipeline now real from Azure SQL → Python extract → Snowflake RAW → dbt → Snowflake STAGING. 59M-row sales × 1969-row calendar LEFT JOIN runs in single-digit seconds.
- **Permission-boundary gap caught and fixed cleanly.** First `dbt build` bounced off Snowflake RBAC; clean diagnostic discipline (SHOW GRANTS → identify gap → grant once → re-verify) avoided the "throw more grants and hope" trap. Snowflake's ownership model handled the rest. Lesson captured in LEARNINGS as the headline session 2 entry; `00_provision_account.sql` updated so future fresh setups don't repeat the gap.
- **Three dbt patterns shipped that will be reused throughout the project:** (a) `{{ source() }}` for RAW table references + sources.yml decoupling, (b) `{{ ref() }}` for cross-model references + automatic DAG building, (c) the CTE chain pattern for any non-trivial model with debugging-by-swapping-the-final-SELECT.
- **The LEFT-JOIN-as-sentinel pattern goes mainstream.** First explicit use in `stg_m5_sales_train` — defensive practice that surfaces data drift (calendar mismatches) as test failures instead of silent row drops. Will reuse on every staging/intermediate join going forward.
- **10-point audit applied honestly.** 8 ✅, 1 ⚠️ (sqlfluff, deferred to Phase 6 by plan), 1 ⚠️ closed in-session (Snowsight eyeball SELECTs confirmed the date cast, SNAP rename, join translation, units_sold rename all worked at the row level).

**Next session (Phase 4 session 3):**

1. Install the `dbt_utils` package via `packages.yml` + `dbt deps` — opens up `generate_surrogate_key`, `unique_combination_of_columns`, and many other helpers.
2. Add a compound-key uniqueness test on `stg_m5_sell_prices` `(store_id, item_id, wm_yr_wk)` now that `dbt_utils.unique_combination_of_columns` is available.
3. First intermediate model — `int_sales_with_prices`. Joins `stg_m5_sales_train` to `stg_m5_sell_prices` via `wm_yr_wk` to attach a price to every sale row. Adds the revenue calculation (`units_sold * sell_price` AS `revenue_amount_usd`).
4. Open the warehouse layer with `dim_calendar` — first dimension table, surrogate key via `dbt_utils.generate_surrogate_key`. Easy first dim because the source is already mostly a star-friendly shape.
5. 10-point audit + doc updates + commit.

---

**Last action (2026-05-15 — Phase 4 session 1):** Scaffolded the dbt project from scratch using hand-scaffold (not `dbt init`) — every file authored deliberately. `dbt-snowflake 1.11.5` installed into existing `.venv` alongside the Phase 3 Airflow stub; pip surfaced the expected "multiple tools in one venv" warnings — all harmless, no dbt-side impact (see LEARNINGS). Wrote `dbt/dbt_project.yml` and `dbt/profiles.yml` (clean professional versions, walkthrough lives in new `DBT_PIPELINE.md`). `.gitignore` line 14 had a blanket `profiles.yml` ignore — added a `!dbt/profiles.yml` exception because our profile uses `env_var()` and is safe to commit. `dbt debug` passes end-to-end. **Mid-session pacing & teaching-format refinements** captured in `TEACHING_PREFERENCES.md`: (a) comments-above-the-line for inline code explanations (never end-of-line — horizontal scroll breaks reading flow); (b) three-layer pattern for every code-shaped file going forward — verbose-version-in-chat, clean-version-on-disk, walkthrough-doc-alongside.

**Files added this session (Phase 4 session 1):**

- `dbt/dbt_project.yml` — master dbt config. Project name `retail_demand_forecasting`, profile pointer, model folder layout, materialization defaults per layer (staging=view, intermediate=view, warehouse=table, marts=table). Clean professional version (~35 lines); depth lives in `DBT_PIPELINE.md`.
- `dbt/profiles.yml` — Snowflake connection details. Every credential via `env_var()` — file is safe to commit. One target (`dev`); production team would add `prod`.
- `dbt/models/staging/.gitkeep`, `dbt/models/intermediate/.gitkeep`, `dbt/models/warehouse/.gitkeep`, `dbt/models/marts/.gitkeep` — empty placeholder files so Git tracks the model folder skeleton ahead of actual models landing.
- `DBT_PIPELINE.md` — new walkthrough doc at project root, matches the `EXTRACT_PIPELINE.md` pattern from Phase 2. Covers the dbt big picture, five-layer architecture, project layout, line-by-line walkthrough of `dbt_project.yml`, full `profiles.yml` walkthrough including the PowerShell `.env` loader, schema-separation TODO, and `dbt debug` verification. Will be extended as Phase 4 progresses.

**Files updated this session (Phase 4 session 1):**

- `requirements.txt` — added Phase 4 section with `dbt-snowflake>=1.11.0` (minimum-version pin only at this stage; lockfile generated end of Phase 4). dbt-core pulled in as transitive dependency.
- `.gitignore` — line 14 split into two lines: kept the blanket `profiles.yml` ignore, added `!dbt/profiles.yml` un-ignore exception immediately below. Standard Git pattern; order matters (un-ignore must follow the ignore).
- `TEACHING_PREFERENCES.md` — added two new sub-bullets under the existing "Show actual code changes inline" rule: (a) **comments-above-the-line, never end-of-line** — applies to YAML, JSON, Dockerfile, any config file Claude walks through with line-by-line annotations. End-of-line comments push past chat code-block width and force horizontal scroll. (b) **three-layer pattern for code-shaped files** — verbose-in-chat (Phil's learning artefact) + clean-on-disk (what ships to git) + walkthrough-md-alongside (portfolio-depth doc).
- `LEARNINGS.md` — populated the dbt section with 10 substantive entries (install drift with Airflow stub, three-layer doc pattern, comments-above-line, the two-file dbt_project.yml/profiles.yml split, env_var(), PowerShell .env loader, .gitignore un-ignore syntax, schema-concatenation gotcha, materialized options + kitchen analogy, `dbt debug` as the canary).
- `PROJECT_CONTEXT.md` — this file, session 1 closeout.

**Headline outcomes from this session:**

- **dbt-Snowflake connection verified end-to-end.** `dbt debug` returns `Connection test: [OK connection ok]` and `All checks passed!`. Every env-driven credential (account, user, password, role, warehouse, database) resolves through `env_var()` from `.env`. Password correctly masked in stdout — secrets pattern works as designed.
- **Hand-scaffold instead of `dbt init`.** Deliberate choice — no example boilerplate to delete, `profiles.yml` lives *in* the repo (portfolio-readable) rather than in `~/.dbt/` (invisible to anyone cloning the repo). Same starting state a senior engineer would produce when bootstrapping a greenfield dbt project at a real company.
- **Three-layer documentation pattern locked in for the rest of the project.** Every code-shaped file from here on follows verbose-in-chat / clean-on-disk / walkthrough-md-alongside. `DBT_PIPELINE.md` is the first instance and will be extended as Phase 4 progresses.
- **TEACHING_PREFERENCES.md evolved twice mid-session.** Phil pushed back on (a) heavily-commented YAML being unsuitable for a portfolio and (b) end-of-line comments forcing horizontal scroll in chat. Both refinements captured as durable rules — applies across all future code-shaped work in Project 2 and any Project 3.
- **Schema-separation TODO open.** `profiles.yml` currently has `schema: RAW` via the env var as a placeholder. `dbt debug` is safe with this (no materialization), but before any `dbt run` lands a real model we need a custom `generate_schema_name.sql` macro plus `+schema:` per folder so staging/intermediate/warehouse/marts go to their own schemas (not `RAW_STAGING` etc). First step of Phase 4 session 2.

**Next session (Phase 4 session 2):**

1. Per-layer schema separation — `macros/generate_schema_name.sql` + `+schema:` per folder in `dbt_project.yml`. **Must happen before any `dbt run`.**
2. `sources.yml` declaring CALENDAR / SELL_PRICES / SALES_TRAIN as the M5 source. Column documentation + freshness checks against `loaded_at`. Verify with `dbt source freshness`.
3. First two staging models — `stg_m5_calendar` and `stg_m5_sell_prices`. Lower complexity — type casting, renaming, no shape change. Adds first dbt tests (`unique`, `not_null` on PK columns).
4. `stg_m5_sales_train` — the substantive staging model. RAW is already long (pandas.melt during Phase 1 load); staging joins to `stg_m5_calendar` to translate `d_NNNN` strings to real DATEs. This `sale_date` is what `fact_daily_sales` will eventually cluster on.
5. `dbt build`, verify all green, 10-point code-quality audit, doc updates + commit.

---

**Last action (2026-05-15 — Phase 3 session 2):** Added `verify_one_day` task downstream of `extract_one_day` in `m5_daily_extract`. Three independent Snowflake-side checks (CALENDAR = 1 row, SELL_PRICES > 0, SALES_TRAIN > 0) batched into one SQL round-trip. **Caught a real silent failure within 10 minutes of deployment** — today's `2026-05-15` auto-fire (no M5 data for that date) returned 0 rows from extract without error; verify queried Snowflake, found 0 rows on all three checks, raised RuntimeError, task square went red. Pipeline correctly reported "the data did not actually land." UI trigger form enabled via `AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS=true`; 20-minute UI gotcha around play-arrow vs `w/ config` buttons documented in LEARNINGS. Test trigger for `2014-01-04` via UI form: extract + verify both green end-to-end.

**Files added this session (Phase 3 session 2):**

- `docs/screenshots/00_verify_caught_silent_failure_2026-05-15_log.png` — Airflow task Logs view showing the three CALENDAR/SELL_PRICES/SALES_TRAIN count lines plus the RuntimeError raised when verify caught the silent failure. Interview-ready evidence.
- `docs/screenshots/01_ui_trigger_form_with_date_picker.png` — the trigger-with-config form filled in for 2014-01-04, showing the Logical Date field, Run id, Configuration JSON, before clicking Trigger. Demonstrates the UI form working.

**Files updated this session (Phase 3 session 2):**

- `airflow/dags/m5_daily_extract.py` — added `verify_one_day` @task downstream of `extract_one_day`, plus `import logging` at module top. Single-SELECT three-COUNT verification query, three positional `%s` binds, per-check logging via `logging.getLogger("airflow.task")`. Task chain wired via `extract_one_day() >> verify_one_day()`. Now 213 lines (was 134).
- `airflow/docker-compose.yml` — added `AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS: 'true'` to the shared `x-airflow-common.environment` block with a 3-line comment. Required full `down` + `up -d` cycle to take effect.
- `LEARNINGS.md` — three new entries under the Airflow section: (a) verify_one_day caught a real silent failure on first deploy, (b) `SHOW_TRIGGER_FORM_IF_NO_PARAMS=true` + the two-button UI gotcha, (c) harmless `core/sql_alchemy_conn` deprecation warning.
- `README.md` — three light-touch edits: Status line updated to Phase 3 closed / Phase 4 next; Airflow bullet enhanced to mention independent verify tasks ("catch silent failures inside the DAG"); `CODE_QUALITY.md` reference updated 9-point → 10-point.
- `PROJECT_PLAN.md` — five stale-bit refreshes earlier in the session (Source DB row, pre-flight checklist, decisions-confirmed section, Status block, header date). Already committed and pushed as commit `9e25491`.
- `PROJECT_CONTEXT.md` — this file, session 2 closeout.

**Files added this session (Phase 3 session 1):**

- `airflow/Dockerfile` — custom image extending `apache/airflow:2.10.3-python3.11`, layering on Microsoft ODBC Driver 17 + a minimal `requirements-airflow.txt`. Versions single-sourced via ARG above FROM.
- `airflow/docker-compose.yml` — postgres metadata DB + idempotent init + webserver + scheduler. LocalExecutor. `env_file: ../.env` for Azure SQL + Snowflake creds. `../scripts:/opt/airflow/scripts:ro` mount so the DAG can call the existing extract module.
- `airflow/requirements-airflow.txt` — minimal extras (pyodbc, python-dotenv, snowflake-connector-python[pandas]) with no version pins; let Airflow's constraints file decide versions.
- `airflow/dags/m5_daily_extract.py` — first DAG. `@daily`, `start_date=2014-01-01 Australia/Melbourne`, `catchup=False`, `max_active_runs=1`, `retries=2`. Single `@task` wraps `extract_azure_to_snowflake.main()` via `sys.argv` shim. Tags: `m5`, `extract`, `phase3`.
- `airflow/README.md` — boot/shutdown/diagnostics cheatsheet for the stack. Quick-start commands, common gotchas, layout reference.
- `pyrightconfig.json` (project root) — `extraPaths: ["scripts"]` so Pylance resolves the DAG-side `import extract_azure_to_snowflake` against the actual module on the host. Tool-agnostic editor config.
- `sql/verify/03_phase3_dag_extract_verification.sql` — independent Snowflake-side verification of the first two Airflow-orchestrated extracts. Four detailed sections + a Section 5 PASS/FAIL rollup using the CTE pattern.

**Files updated this session:**

- `scripts/extract_azure_to_snowflake.py` — added `wake_azure_sql()` helper for retry-on-40613/40197, wired into `main()` between `connect_azure_sql()` and `connect_snowflake()`. Also added CLI-contract note in the module docstring warning that the DAG depends on `--run-date`.
- `CODE_QUALITY.md` — added new criterion 6 "Dev environment hygiene"; renumbered existing 6→7, 7→8, 8→9, 9→10; "six core checks" → "seven core checks". Triggered by yellow-squigglies-on-DAG-file mid-session.
- `TEACHING_PREFERENCES.md` — mirrored the criterion 6 addition. Plus added an explicit rule about showing code changes inline (with line numbers, file paths, before/after) for code-shaped files but not for doc-shaped files. Refined twice through the session as Phil clarified preferences.
- `LEARNINGS.md` — eight new entries across the Airflow section: stack architecture, custom-image SQLAlchemy/constraints story, Docker-daemon-must-run, code-quality framework gap, Airflow 2.x CLI flag versioning (`-e` not `--logical-date`), `catchup=False` semantics on unpause, CTE-based PASS/FAIL pattern.
- Local `.venv` — `pip install pendulum "apache-airflow==2.10.3" --no-deps` to give Pylance enough to resolve airflow imports without dragging in Windows-incompatible transitive deps.

**Headline outcomes from this session:**

- **First DAG end-to-end working.** `m5_daily_extract` triggered twice via Airflow CLI (`docker compose exec airflow-scheduler airflow dags trigger m5_daily_extract -e <date>`), both runs landed real rows in Snowflake. 2014-01-01: 1 + 25,939 + 30,490 = 56,430 rows. 2014-01-02: same shape (sell_prices shares the fiscal week, so the same 25,939 rows back the second date too).
- **Verification clean.** Independent Snowflake-side SQL (`sql/verify/03_phase3_dag_extract_verification.sql`) returned 6 PASS, 0 FAIL. Both script-internal parity and downstream double-check aligned.
- **The wake helper earned its keep on its first real run.** When the manual smoke test ran in PowerShell after lunch, Azure SQL had auto-paused; `wake_azure_sql` caught 40613, slept 45s, retried, succeeded. Exactly the failure mode predicted in `LEARNINGS` during Phase 2 session 3 — now covered.
- **Code-quality framework grew during the session.** Yellow Pylance squigglies on the freshly-written DAG file revealed the original 9 criteria didn't cover dev-environment hygiene. Added criterion 6 and renumbered the rest. The framework now catches this class of issue going forward.
- **Mid-session pacing refinement.** Phil pushed back on "lots of changes summarised in bullets, hard to follow." `TEACHING_PREFERENCES.md` updated twice to capture an explicit rule for inline code display (path + line numbers + before/after for code-shaped files; description-only for doc-shaped).

**Next session (Phase 3 session 2) — Airflow polish + scheduled-run observation:**

- Toggle DAG back off between sessions OR let the daily schedule walk forward and observe live. If left running, by next session there should be 1-3 additional auto-fired runs in the metadata DB (2026-05-15, 16, 17), which is itself useful as a demo of "Airflow runs by itself."
- Add a downstream Snowflake-side verification task to the DAG. Two-task DAG: `extract_one_day` → `verify_one_day`. The verify task queries Snowflake and confirms the row count matches what the script reported. Closes the loop inside Airflow rather than relying on a manual SQL run.
- Consider `AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS=true` in docker-compose so future manual triggers can use the UI form (with calendar date picker) rather than the CLI. Requires `down`+`up` cycle to take effect.
- Document the run in the README's architecture diagram so the new Airflow section in the public README has a concrete example of an Airflow-orchestrated extract.
- Stretch: VS Code Dev Containers as a Phase 6 polish item — attaches the editor *into* the running Airflow container, eliminating any Windows-host vs Linux-runtime drift. Real-DE-shop pattern, strong interview talking point.

---

## Pre-flight check results

| Check                    | Result                                     | Implication                                        |
| ------------------------ | ------------------------------------------ | -------------------------------------------------- |
| RAM                      | 31.7 GB total                              | Full Docker stack supported, no compromises needed |
| Docker Desktop           | ✅ Installed (v29.4.2), WSL 2 backend      | Ready for Phase 3 (Airflow)                        |
| Python                   | ✅ 3.11.9 available                        | Sufficient (need 3.11+)                            |
| Git / GitHub             | ✅ Working, repo created and pushed        | Public repo live                                   |
| Kaggle account           | ✅ Active, phone verified                  | Can use API                                        |
| Kaggle API token         | ✅ kaggle.json in `C:\Users\Phil\.kaggle\` | Ready for scripted download                        |
| Azure subscription       | ✅ Active, Owner role, $0 current spend    | Will use Azure SQL Database from Phase 1           |
| Power BI Service licence | None — Power BI Free Desktop only          | Build in Desktop, screenshots in README            |
| Snowflake                | NOT signed up yet (intentional)            | Sign up in Phase 2 only                            |

---

## Locked decisions

See `PROJECT_PLAN.md` for the full table. Key updates since the original plan:

- **Source database:** Azure SQL Database Serverless General Purpose (NOT Docker locally) — committed in Phase 1
- **Azure budget alert:** $50/month — to set up in Phase 1
- **Ingestion pattern:** Simulated freshness via date-partitioned incremental extraction (Option B). All M5 history loaded once into Azure SQL; each scheduled Airflow run extracts one new date slice. Locked 2026-05-12.
- **Phase ordering:** Airflow stays in Phase 3 (before dbt + Power BI). Decision confirmed 2026-05-12 — matches how production pipelines actually grow.
- **All other locked decisions:** unchanged from `PROJECT_PLAN.md`

---

## Phase 0 deliverables (completed)

- ✅ Folder renamed to `retail-demand-forecasting-project`
- ✅ Foundational docs created: `PROJECT_PLAN.md`, `PROJECT_CONTEXT.md`, `LEARNINGS.md`, `TEACHING_PREFERENCES.md` (copied from Project 1)
- ✅ `README.md` skeleton with architecture diagram, tech stack, project context
- ✅ `.gitignore` covering secrets, data, Python, dbt, Airflow, Docker, IDE artefacts
- ✅ Docker Desktop installed and verified (v29.4.2)
- ✅ Git repo initialised, branch renamed to `main`
- ✅ First commit made with Phase 0 scaffolding (6 files, 773 insertions)
- ✅ Public GitHub repo created at `https://github.com/Pheluciam/retail-demand-forecasting-project`
- ✅ First commit pushed to GitHub `main`
- ✅ Kaggle account active, phone verified, API token (`kaggle.json`) saved to `C:\Users\Phil\.kaggle\`

---

## Phase 1 — full checklist (all complete)

1. ✅ Resource Group + $50 AUD budget alert
2. ✅ Azure SQL Database (Serverless General Purpose Free tier with auto-pause)
3. ✅ Firewall rule for client IP (`115.69.3.187`)
4. ✅ M5 dataset downloaded from Kaggle to `data/raw/`
5. ✅ Python venv + `requirements.txt` installed
6. ✅ Smoke-test pyodbc connection to Azure SQL
7. ✅ 3 raw tables created (`raw.calendar`, `raw.sell_prices`, `raw.sales_train`) — DDL idempotent, PAGE-compressed
8. ✅ Loader script (`scripts/load_m5_to_azure_sql.py`) — pandas + SQLAlchemy + fast_executemany
9. ✅ Overnight bulk load — 3 tables, ~12 hours total
10. ✅ Post-load verification — row counts + schema + eyeball sample rows all OK (`sql/verify/01_phase1_load_verification.sql`)
11. ✅ Documentation closeout — LEARNINGS + PROJECT_CONTEXT + CODE_QUALITY updated

**Overnight-stability power settings reverted on 2026-05-13 morning.** Nothing pending.

---

## Phase 2 progress

**Phase 2 = Snowflake + extraction.** Estimated 2–3 sessions. Session 1 done.

### Session 1 (2026-05-13 afternoon — ✅ DONE)

1. ✅ Snowflake free trial signed up — Standard edition, AWS, `ap-southeast-2` (Sydney), account `ghrcrqs-hw63290`
2. ✅ Provisioned in Snowflake: warehouse `WH_RETAIL` (XS, auto-suspend 60s), database `RETAIL_DB`, schema `RAW`, role `RETAIL_ENGINEER`, all grants, role hierarchy
3. ✅ Snowflake creds in `.env` (password gitignored); `.env.example` updated with non-secret values
4. ✅ `snowflake-connector-python[pandas]>=3.0.0` added to `requirements.txt` and installed (resolved to v4.5.0)
5. ✅ `scripts/smoke_test_snowflake.py` — connector smoke test passing
6. ✅ `sql/snowflake/01_create_raw_tables.sql` — three RAW tables (CALENDAR, SELL_PRICES, SALES_TRAIN) with `loaded_at` audit cols + Melbourne timezone applied
7. ✅ Locked design decision: backfill cutoff at **2014-01-01** (see `LEARNINGS.md`)

### Session 2 (2026-05-13 late afternoon — ✅ DONE)

1. ✅ `scripts/extract_azure_to_snowflake.py` written — date-parameterised, idempotent, ~440 lines incl. comments
2. ✅ Smoke-tested on increasing windows (1 day calendar, idempotent re-run, 1 day all tables, 7 days all tables); 213,430 sales_train rows verified for the 7-day test
3. ✅ Mid-test 9-point audit completed; three real findings logged (`Connection Timeout=` gotcha, scan-cost economics, transient retry behavior) — all addressed or documented in LEARNINGS
4. ✅ LEARNINGS + PROJECT_CONTEXT updated

### Session 3 (2026-05-14 morning — ✅ DONE)

1. ✅ Windows sleep settings → Never for the duration; reverted post-backfill.
2. ✅ 3-year backfill executed in one invocation:
   ```powershell
   python scripts/extract_azure_to_snowflake.py --start-date 2011-01-29 --end-date 2013-12-31
   ```
   **Wall-clock: 27.3 min** (vs 60-90 min predicted, vs 40-hour original fear).
3. ✅ End-to-end parity verified two ways:
   - Script-internal: source count == written count for all three tables.
   - Independent SQL: `sql/snowflake/02_extract_smoke_tests.sql` Section 5 + `sql/verify/02_phase2_extract_verification.sql` — all three tables `OK`.
4. ✅ Documentation updates: `LEARNINGS.md` (3 entries added), `EXTRACT_PIPELINE.md` (new interview walkthrough), `sql/snowflake/02_extract_smoke_tests.sql` (Section 5), `sql/verify/02_phase2_extract_verification.sql` (new file), `PROJECT_CONTEXT.md` (this file).
5. ✅ Git add + commit + push (Phase 2 closeout commit).

**Phase 2 closed.** Phase 3 (Airflow) opens the next session.

### Quick start for Phase 3 session 1 (Airflow)

```powershell
cd C:\Users\Phil\Documents\Claude\Projects\retail-demand-forecasting-project
.\.venv\Scripts\Activate.ps1
# Re-anchor Claude on PROJECT_CONTEXT.md + TEACHING_PREFERENCES.md + LEARNINGS.md
# Verify Docker Desktop is running: docker --version
# Then start building docker-compose.yml for the Airflow stack.
```

---

## Phase 3 progress

**Phase 3 = Orchestration with Airflow.** Estimated 2–3 sessions. Session 1 done.

### Session 1 (2026-05-14 afternoon — ✅ DONE)

1. ✅ Pre-work: added `wake_azure_sql()` retry helper to `scripts/extract_azure_to_snowflake.py`, covering Azure SQL cold-start error codes 40613 and 40197. 3 attempts × 45s delay. Smoke-tested against a paused DB — caught 40613 on attempt 1, retried, succeeded.
2. ✅ Built Airflow Docker stack: `airflow/Dockerfile` (custom image with msodbcsql17 + minimal requirements pinned to Airflow constraints) + `airflow/docker-compose.yml` (postgres + idempotent init + webserver + scheduler, LocalExecutor, env_file from `../.env`).
3. ✅ Booted the stack — three containers healthy, UI reachable at `localhost:8080` with `airflow`/`airflow` admin login.
4. ✅ Wrote first DAG `m5_daily_extract` using the TaskFlow API (@dag + @task decorators). Calls existing extract script via `sys.argv` shim so the script needs zero changes. Catchup off, max_active_runs=1, retries=2.
5. ✅ Triggered manually for `2014-01-01` and `2014-01-02` via Airflow CLI inside the scheduler container. Both runs landed real rows end-to-end through the orchestrated pipeline.
6. ✅ Verified independently from Snowsight via `sql/verify/03_phase3_dag_extract_verification.sql` — 6 PASS / 0 FAIL using the new CTE-based summary template.

### Mid-session: code-quality framework evolved

- ✅ Yellow Pylance squigglies on the DAG file revealed a gap: original 9 criteria all audited code content, never the dev environment around it. Added criterion 6 "Dev environment hygiene" to `CODE_QUALITY.md` and `TEACHING_PREFERENCES.md`; renumbered the rest (six core checks → seven).
- ✅ Practical fixes for the same gap: `pyrightconfig.json` + `pip install pendulum apache-airflow==2.10.3 --no-deps` to give Pylance enough to resolve DAG imports on Windows without dragging in Airflow's Unix-only transitive deps. Flagged VS Code Dev Containers as a Phase 6 polish improvement.

### Mid-session commit

- ✅ Git commit `d1eee77` — "feat(airflow): Phase 3 session 1 - stack scaffolding + first DAG (pre-trigger)". Pushed to `origin/main`. Captures the stack + DAG before the first trigger fired.

### Session 1 closeout (this commit)

- ✅ Three new LEARNINGS entries: Airflow 2.x CLI flag versioning (`-e` vs `--logical-date`), `catchup=False` unpause semantics, CTE PASS/FAIL pattern.
- ✅ This `PROJECT_CONTEXT.md` updated to reflect Phase 3 session 1 closing.
- ✅ Git commit + push (this commit).

**Phase 3 session 1 closed.** Session 2 opens with Airflow polish: downstream verify task, scheduled-run observation, UI trigger-with-config enabled.

### Session 2 (2026-05-15 — ✅ DONE)

1. ✅ Re-anchored on PROJECT_CONTEXT.md + PROJECT_PLAN.md; refreshed 5 stale spots in PROJECT_PLAN.md and pushed as commit `9e25491` (small docs-only commit early in the session).
2. ✅ Added `verify_one_day` @task downstream of `extract_one_day` in `m5_daily_extract`. Three Snowflake-side checks batched into one SQL round-trip. Task chain: `extract_one_day() >> verify_one_day()`. Per-check logging added.
3. ✅ End-to-end test trigger for `2014-01-03` via Airflow CLI: extract + verify both green. Three count log lines visible: CALENDAR=1, SELL_PRICES=25,939, SALES_TRAIN=30,490.
4. ✅ **Real silent failure caught:** today's `2026-05-15` auto-fire upon unpause extracted 0 rows (no M5 data for that date), extract returned cleanly, verify raised RuntimeError on all three checks. Exactly the failure mode the verify task was built to catch.
5. ✅ Enabled UI trigger-with-config form via `AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS: 'true'` in docker-compose.yml. Full `down` + `up -d` cycle to apply. Diagnosed via `docker compose exec airflow-webserver airflow config get-value webserver show_trigger_form_if_no_params` → returned `true`.
6. ✅ UI gotcha resolved: Airflow 2.10 has two trigger buttons. Play-arrow always quick-fires; "Trigger DAG w/ config" (dropdown) opens the form. ~20 min lost; full diagnosis in LEARNINGS.
7. ✅ Test UI trigger for `2014-01-04T00:00:00+00:00` via the form: extract + verify both green. Screenshot saved.
8. ✅ README.md refreshed (3 light edits) — status line, Airflow bullet, code-quality reference. Bigger README rewrite remains in Phase 6.
9. ✅ LEARNINGS.md updated with three entries; PROJECT_CONTEXT.md updated (this file); git add + commit + push.

**Phase 3 closed.** Both technical sessions done; remaining stretch items (Dev Containers) rolled into Phase 6 polish per the original plan. **Phase 4 (dbt transformations) opens the next session.**

---

## Phase 4 progress

**Phase 4 = dbt transformations.** Estimated 3–4 sessions. Session 1 done.

### Session 1 (2026-05-15 — ✅ DONE)

1. ✅ `dbt-snowflake 1.11.5` installed into existing `.venv` via `pip install dbt-snowflake`. Resolved alongside Phase 3's `--no-deps` Airflow stub — surfaced expected "multiple tools in one venv" pip warnings; all harmless. Full diagnosis in LEARNINGS.
2. ✅ Hand-scaffolded dbt project structure (chose this over `dbt init` for portfolio cleanliness — no example boilerplate to delete, `profiles.yml` lives *in* the repo where it's visible to anyone cloning).
3. ✅ Wrote `dbt/dbt_project.yml` — project name `retail_demand_forecasting`, materialization defaults per layer (staging=view, intermediate=view, warehouse=table, marts=table). Clean professional version (~35 lines); depth lives in new `DBT_PIPELINE.md`.
4. ✅ Wrote `dbt/profiles.yml` — every credential via `env_var()`. File is safe to commit. `.gitignore` updated with `!dbt/profiles.yml` exception (line 14-15) to override the dbt-community-default blanket ignore on `profiles.yml`.
5. ✅ Empty model folders + `.gitkeep` placeholders: `models/staging/`, `models/intermediate/`, `models/warehouse/`, `models/marts/`.
6. ✅ `requirements.txt` updated with `dbt-snowflake>=1.11.0` under a new Phase 4 section (minimum-version pin; lockfile generation deferred to end of Phase 4).
7. ✅ `dbt debug` passes end-to-end against `RETAIL_DB.RAW` via `WH_RETAIL`. Every env-driven credential (account, user, password, role, warehouse, database) resolves correctly. Password masked in stdout — secrets pattern works as designed.
8. ✅ Two mid-session `TEACHING_PREFERENCES.md` refinements after Phil pushed back on verbosity: (a) **comments-above-the-line** for inline code explanations (never end-of-line — horizontal scroll in chat breaks reading flow); (b) **three-layer pattern** for every code-shaped file going forward — verbose-in-chat + clean-on-disk + walkthrough-md-alongside.
9. ✅ `DBT_PIPELINE.md` created as the first instance of the three-layer pattern (matches Phase 2's `EXTRACT_PIPELINE.md`). Covers dbt big picture, five-layer architecture, project layout, line-by-line walkthroughs of `dbt_project.yml` and `profiles.yml`, the `.env` loading prerequisite, and `dbt debug` verification. Will be extended each session.
10. ✅ `LEARNINGS.md` dbt section populated with 10 substantive entries.

### Quick start for Phase 4 session 2

```powershell
# 1. Move into the project + activate venv
cd C:\Users\Phil\Documents\Claude\Projects\retail-demand-forecasting-project
.\.venv\Scripts\Activate.ps1

# 2. Re-anchor Claude on (in order):
#    PROJECT_CONTEXT.md  → TEACHING_PREFERENCES.md
#    LEARNINGS.md        → PROJECT_PLAN.md
#    DBT_PIPELINE.md     ← new this phase, the dbt walkthrough

# 3. Load .env into the PowerShell session — REQUIRED before any dbt command
Get-Content .env | ForEach-Object {
    if ($_ -match '^([A-Z_][A-Z0-9_]*)=(.*)$') {
        [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
    }
}

# 4. Sanity-check dbt is still healthy
cd dbt
dbt debug   # expect: All checks passed!
```

**First Phase 4 session 2 step:** wire up per-layer schema separation
(custom `macros/generate_schema_name.sql` + `+schema:` per folder in
`dbt_project.yml`) — **must happen before any `dbt run`**. Then
`sources.yml` for the three RAW tables (CALENDAR, SELL_PRICES,
SALES_TRAIN) with `loaded_at` freshness checks. Verify with
`dbt source freshness`. Then first staging models.

Airflow stack does **not** need to be running for Phase 4 work — dbt
talks to Snowflake directly. Boot Docker only if you want to demo
a DAG run.

---

## Key reference files

- `PROJECT_PLAN.md` — static plan, scope, timeline, locked decisions, risks
- `TEACHING_PREFERENCES.md` — how Phil works with Claude (carry-forward from Project #1, plus SQL CAPS preference and Project 2 pacing notes)
- `LEARNINGS.md` — running journal of lessons learned (populated as we go)
- `LEARNING_ROADMAP.md` — forward-looking learning pathway beyond Project #2 (incl. planned post-Project-#3 six-week Python deep dive)
- `EXTRACT_PIPELINE.md` — Phase 2 walkthrough for the Azure SQL → Snowflake extract path (interview-ready)
- `DBT_PIPELINE.md` — Phase 4 walkthrough for the dbt transformation pipeline (interview-ready, extended each session)
- `CODE_QUALITY.md` — the 10-point code-quality audit checklist applied to every non-trivial script
- `README.md` — public-facing project intro for hiring managers (built up over Phase 6)
- `.gitignore` — files Git should ignore (secrets, data, build artefacts)

---

## Project #1 reference

For carry-forward learnings and patterns:

- `C:\dbt\cdc_nt_gtfs\TEACHING_PREFERENCES.md` (canonical version — kept in sync with our copy)
- `C:\dbt\cdc_nt_gtfs\LEARNINGS.md` (Project #1 lessons)
- `C:\dbt\cdc_nt_gtfs\NEXT_PROJECT.md` (the roadmap that informed this project)

---

## Public GitHub repo

https://github.com/Pheluciam/retail-demand-forecasting-project
