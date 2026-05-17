# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Live state of the project. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-17 (Phase 4 session 6 closed — Airflow ↔ dbt integration via **Astronomer Cosmos**. DAG extended from 2 tasks to 4: `extract_one_day → verify_one_day → [dbt_models task group, 18 auto-generated tasks] → verify_dbt_one_day`. Cosmos parses the dbt project at DAG-parse time and generates one Airflow task per dbt model + per test, with per-model lineage visible in the Airflow Graph view. End-to-end manual trigger for logical_date 2014-03-23 (ds 2014-03-22) ran all 4 stages green in 5:31. Failure-injection test confirmed clean chain halt via `upstream_failed` propagation. **Phase 4 complete.** Scope-expansion decision locked end-of-session: **Phase 5 + Phase 6 now run with full scope (no optionals)** — forecasting layer + GitHub Actions CI + dbt docs on GitHub Pages all promoted from stretch to baseline. Phase 5 expanded from 2-3 sessions to 5-6; Phase 6 from 1-2 to 2-3. Next: Phase 5 session 1 = Snowflake connection + Home page + semantic model in Power BI).

---

## Where we are right now

**Current phase:** **Phase 4 session 6 ✅ DONE — Phase 4 COMPLETE.** Airflow ↔ dbt integration via **Astronomer Cosmos** shipped end-to-end. The `m5_daily_extract` DAG extended from 2 tasks (`extract_one_day → verify_one_day`) to 4 (`extract_one_day → verify_one_day → [dbt_models task group, 18 auto-generated tasks] → verify_dbt_one_day`). Cosmos reads the dbt project's manifest at DAG-parse time and generates one Airflow task per dbt model + one per dbt test (default `test_behavior=AFTER_EACH`), with the Airflow Graph view showing the dbt DAG directly. End-to-end manual trigger for logical_date 2014-03-23 (processing `ds`=2014-03-22) ran all 4 stages green in **5:31**: extract green → verify green → 9 dbt model `run` + 9 model `test` tasks all green inside `dbt_models` → verify_dbt_one_day's 9 cross-layer row-count checks all pass. **Failure injection test** (flipped mart's `active_store_count` accepted_range `max_value: 10 → 5`, triggered fresh run) confirmed clean chain halt: `dbt_models` went red on the broken mart test, `verify_dbt_one_day` went `upstream_failed` with `Duration=00:00:00` (never executed), overall DAG run failed. YAML reverted post-test; project state clean. **Three real engineering gotchas** captured: Cosmos's lazy-imports gotcha (Pylance fix via submodule paths `cosmos.airflow.task_group` and `cosmos.config`); dbt-core/adapter version-pinning across the 1.8+ decoupling (`dbt-snowflake==1.11.5` requires `dbt-core>=1.11.6`, so we pinned `dbt-core==1.11.10 + dbt-snowflake==1.11.5`); incremental fact backfill limitation (the standard `WHERE sale_date > MAX(sale_date)` pattern is forward-only — got bit by first test trigger landing on 2014-01-04, before the existing fact's max of 2014-03-21). All three now durable LEARNINGS entries. **One self-inflicted UI mistake** captured: conflating Airflow's page-level trash icon with the panel-level trash wiped DAG history (cosmetic loss only — DAG file untouched, Snowflake data untouched, scheduler re-parsed and DAG reappeared with no history). Documented as a teaching-discipline lesson. **The headline DE portfolio narrative is now real**: *"end-to-end pipeline on a schedule with proper failure handling, tests, and per-model lineage visibility — a broken dbt test halts the chain at that exact task, the downstream verify never fires on broken data, and the Airflow UI tells me which model in which layer broke without grepping logs."* 13 lines of Cosmos config replaced what would have been ~150 lines of hand-wired BashOperator tasks. **Phase 5 session 1 next**: Power BI dashboard build, connecting Snowflake's `WAREHOUSE.fact_*` + `dim_*` directly for analyst-facing pages, with `mart_executive_overview` powering the home page.

**Last action (2026-05-17 — Phase 4 session 6):** Closed Phase 4 with the Cosmos integration. **Three pieces of installation surface** wired in: `astronomer-cosmos>=1.7,<2.0` added to `airflow/requirements-airflow.txt` (range-pinned because Cosmos ships breaking changes between major versions; documented as deliberate departure from the file's existing no-pin convention); separate Python venv at `/opt/airflow/dbt_venv` baked into the Dockerfile with `dbt-core==1.11.10 dbt-snowflake==1.11.5` (Astronomer's documented pattern — dbt's pinned shared deps `jinja2`/`pyyaml`/etc conflict with Airflow's constraints file, so isolation in a separate venv is the senior move); `../dbt:/opt/airflow/dbt:ro` volume mount added to `docker-compose.yml` (read-only window for Cosmos to read dbt_project.yml + the models/ folder at DAG-parse time). DAG file (`airflow/dags/m5_daily_extract.py`) extended with **Cosmos imports using submodule paths** (`from cosmos.airflow.task_group import DbtTaskGroup` + `from cosmos.config import ExecutionConfig, ProfileConfig, ProjectConfig` — the natural `from cosmos import ...` failed Pylance with "Object of type object is not callable" because Cosmos uses lazy imports via `__getattr__`), module-level Cosmos config block (`project_config`, `profile_config` pointing at the existing `profiles.yml` so both manual + Airflow runs share one credential surface via `env_var()`, `execution_config` pointing at the dbt venv), `DbtTaskGroup` instantiation inside the `@dag` function, and a new `verify_dbt_one_day` @task that mirrors the existing `verify_one_day` pattern with 9 row-count checks across STAGING / INTERMEDIATE / WAREHOUSE / MARTS in a single Snowflake round-trip. Pre-existing `cur.fetchone()` unsafe-unpack pattern in `verify_one_day` corrected with a proper None-guard (always was a latent issue; Pylance flagged it this session). **Three real gotchas hit and resolved mid-session**: (a) initial pin combo `dbt-core==1.11.5 + dbt-snowflake==1.11.5` failed with pip ResolutionImpossible because dbt-snowflake 1.11.5 requires `dbt-core>=1.11.6` since the 1.8 decoupling — fixed by pinning to `dbt-core==1.11.10 + dbt-snowflake==1.11.5` (mismatched patches by design, documented inline); (b) first end-to-end manual trigger for logical_date `2014-01-05` failed at verify_dbt_one_day because the fact's incremental WHERE clause `sale_date > MAX(sale_date)` excluded 2014-01-04 (the `ds` for that logical_date in `@daily` semantics) since the existing fact's MAX is 2014-03-21 — fixed by triggering a date AFTER the max (logical_date 2014-03-23 → ds 2014-03-22 → incremental MERGE picks up the new date cleanly); (c) Airflow's `logical_date` vs `ds` off-by-one in `@daily` schedule semantics surfaced during the trigger UX — logical_date is the END of the data interval, so triggering "2014-03-22" actually processes 2014-03-21. **One self-inflicted UI mistake**: conflated Airflow's page-level trash icon (deletes entire DAG) with panel-level trash (deletes one run) when guiding through a failed-run housekeeping step; accidentally wiped all DAG history. DAG file on disk untouched; scheduler re-parsed and DAG reappeared with zero history. Cosmetic loss only; documented as teaching-discipline carry-forward. **Failure injection test** closed the session: flipped mart's `active_store_count` accepted_range `max_value: 10 → 5`, triggered, observed clean chain halt (`dbt_models` red, `verify_dbt_one_day` `upstream_failed` with `Duration=00:00:00` and `Trigger Rule=all_success`), reverted the YAML. **The chain halts correctly on a broken dbt test, and the downstream verify never fires on broken data.**

**Files updated this session (Phase 4 session 6):**

- `airflow/requirements-airflow.txt` — appended `astronomer-cosmos>=1.7,<2.0` with rationale comment explaining the range-pin departure from the file's existing no-pin convention (Cosmos has independent semver and breaking-change-prone majors).
- `airflow/Dockerfile` — appended new section + `RUN python -m venv /opt/airflow/dbt_venv && /opt/airflow/dbt_venv/bin/pip install --no-cache-dir dbt-core==1.11.10 dbt-snowflake==1.11.5`. Comment block above the RUN line documents the two-venv-with-divergent-patches pattern and the dbt-core/adapter decoupling rationale.
- `airflow/docker-compose.yml` — added `- ../dbt:/opt/airflow/dbt:ro` mount in the shared `x-airflow-common.volumes` anchor (so all three Airflow services inherit it). Same `:ro` pattern as the existing `../scripts` mount from Phase 3.
- `airflow/dags/m5_daily_extract.py` — added Cosmos imports (submodule paths to satisfy Pylance), module-level Cosmos config block (~25 lines: `DBT_PROJECT_PATH`, `DBT_EXECUTABLE_PATH`, `project_config`, `profile_config`, `execution_config`), `DbtTaskGroup` instantiation inside the `@dag` function (13-line block) replacing what would have been ~150 lines of hand-wired BashOperator tasks, new `verify_dbt_one_day` @task (~115 lines mirroring `verify_one_day` pattern), and updated wiring to `extract_one_day() >> verify_one_day() >> dbt_models >> verify_dbt_one_day()`. Pre-existing `cur.fetchone()` None-guard added to `verify_one_day` for typing correctness (3-line replacement of a single-line unpack with a None-check + RuntimeError).
- `TEACHING_PREFERENCES.md` — header date bumped; added one new bullet under "Anything else Claude should know": **"Analogies for architectural and structural explanations."** When explaining how components in the stack talk to each other (Snowflake ↔ Airflow ↔ dbt, container boundaries, volume mounts, environment isolation, why a specific shell command exists in the chain), lead with a real-world analogy — factory floor, restaurant kitchen, office layout, locker-and-rulebook, window-in-the-wall — then layer the technicalities on top. Code walkthroughs themselves don't need analogies (those work fine as verbose-in-chat with comments-above-the-line). Captures Phil's feedback that the factory-floor analogy made the Airflow + dbt + Cosmos topology click, while extending analogies into incremental code edits added noise.
- `DBT_PIPELINE.md` — header date bumped; "Sections to add (Phase 4 closeout)" placeholder replaced with substantial **"Airflow orchestration of dbt — Astronomer Cosmos integration"** section (~250 lines). 13 sub-sections covering: what Cosmos does (vs BashOperator vs hand-wiring); the four-task chain anatomy; three installation pieces; Cosmos config block (ProjectConfig / ProfileConfig / ExecutionConfig); the 13-lines-replace-150 quantification; Cosmos's default `test_behavior=AFTER_EACH`; lazy-imports + submodule workaround; dbt-core/adapter version pinning; Airflow data_interval semantics (`logical_date` vs `ds`); verify_dbt_one_day pattern + 9-check table; incremental fact backfill limitation; failure injection test results; build outcomes + interview talk-track; file-change summary table.
- `LEARNINGS.md` — appended **4 new Airflow entries** (Cosmos per-model task generation as the session-6 headline; Cosmos lazy imports + submodule workaround for Pylance; Airflow data_interval semantics — logical_date vs ds; Airflow task states — upstream_failed vs failed + trigger_rule reference table); **3 new dbt entries** (dbt-core/adapter independent patch cycles since 1.8; incremental fact backfill limitation in forward-only WHERE patterns; failure injection as a validation technique); **1 new Mistakes & diagnoses entry** (page-level vs panel-level trash icon conflation → deleted DAG history → cosmetic loss + teaching-discipline carry-forward); and **populated the previously-empty Pipeline orchestration section** with the two-stage Phase 3 → Phase 4 narrative plus 4 carry-forward principles for Project #3.
- `PROJECT_PLAN.md` — Status block bumped from "Phase 4 — session 5 closed; session 6 next" to "Phase 4 — closed; Phase 5 session 1 next (Power BI dashboard)."
- `README.md` — Status paragraph rewritten to reflect Phase 4 closure + the 4-stage Cosmos-orchestrated DAG; "What this project demonstrates" gained a new bullet on per-model dbt lineage via Cosmos; DBT_PIPELINE bullet in the documentation list updated to mention the Airflow ↔ dbt integration coverage.
- `GLOSSARY.md` — 7 new entries appended to section 6 (Airflow & Orchestration): **Astronomer Cosmos**, **DbtTaskGroup**, **Cosmos ProjectConfig / ProfileConfig / ExecutionConfig**, **logical_date vs data_interval_start vs ds**, **trigger_rule**, **upstream_failed**, **test_behavior (Cosmos)**. Tagged `[Project 2]` where project-specific.
- `LEARNING_ROADMAP.md` — Project #2 status note updated from "🏗 In progress" to "🏗 In progress — Phase 4 closed (Airflow + dbt via Cosmos), Phase 5 (Power BI) next."
- `EXTRACT_PIPELINE.md` — added a "Phases 3 and 4 are now complete" note at the top of the "What's next" section with a cross-reference to `DBT_PIPELINE.md` → "Airflow orchestration of dbt — Astronomer Cosmos integration." The original Phase 2 → Phase 3 framing of the section preserved below the note as historical context.
- `requirements.txt` (project root) — dbt-snowflake pin tightened from `>=1.11.0` (minimum-version) to exact `==1.11.5`; new explicit `dbt-core==1.11.10` pin added; comment block explains the version-number divergence (dbt 1.8+ decoupling) and the lockstep-with-airflow/Dockerfile relationship.
- `PROJECT_CONTEXT.md` — this file. Header date bumped; "Current phase" paragraph rewritten to reflect Phase 4 closure; new session 6 closeout block inserted above the session 5 block; session 5 block preserved as historical record.

**Headline outcomes from this session (Phase 4 session 6):**

- **End-to-end orchestrated pipeline complete.** Azure SQL → Snowflake RAW → staging → intermediate → warehouse → marts → verification, all on a single `@daily` Airflow schedule with proper failure handling, tests, and per-model lineage visibility. The headline DE portfolio narrative is now real, not aspirational.
- **Cosmos's payoff visualised.** 13 lines of Cosmos config in the DAG replaced what would have been ~150 lines of hand-wired BashOperator tasks. The Airflow Graph view shows the dbt DAG directly — screenshot-ready visual for the portfolio. Single source of truth (the dbt project), automatic regeneration at every DAG-parse cycle.
- **Three real engineering gotchas hit and documented** as durable LEARNINGS entries useful for interview deep-dives: (a) Cosmos lazy imports + submodule workaround for Pylance; (b) dbt-core/adapter version pinning since the 1.8 decoupling; (c) incremental fact backfill limitation in forward-only WHERE patterns. Each is a credible "I hit this, I diagnosed it, I fixed it" story.
- **Failure injection earned its keep on its first run.** Closing validation produced concrete evidence that the chain halts cleanly on a dbt test failure — `dbt_models` red, `verify_dbt_one_day` `upstream_failed` with `Duration=00:00:00` confirming the downstream verify never fired. Clean revert leaving project state intact.
- **One self-inflicted UI mistake captured as a teaching-discipline lesson** (page-level vs panel-level trash icon confusion → DAG history wipe). Cosmetic loss only; DAG file untouched, Snowflake data untouched. The discipline rule going forward — "name the EXACT screen region a button is in, not just the button shape" — is now a durable LEARNINGS entry.
- **Headline metrics**: 4 outer task squares green for 2014-03-22 trigger; 21 total tasks in the DAG (3 @tasks + 18 auto-generated dbt tasks); 5:31 end-to-end DAG run duration; 78 dbt test assertions running inside 9 model-level test tasks; all 9 row-count checks in verify_dbt_one_day passing on the success run.

**Phase 4 complete. Next: Phase 5 (Power BI + forecasting) — full scope locked 2026-05-17, no optionals:**

The pipeline now stands end-to-end with Airflow orchestration, dbt transformations, and Snowflake as the analytical warehouse. Phase 5 ships the Power BI dashboard layer + the forecasting layer that feeds the Forecast vs Actual page. Phase 6 then closes the project with CI/CD + final polish. Both phases now run with everything baseline (former stretch goals promoted). See `PROJECT_PLAN.md` → "Session-by-session timeline" + "Definition of shippable" for the locked contract.

**Phase 5 session-by-session breakdown (5-6 sessions):**

1. **Session 5.1 — Snowflake connection + Home page + semantic model.** Native Snowflake connector with DirectQuery vs Import evaluation; settle the pattern empirically per page (~1k mart rows on home, ~32.9M fact rows on slicing pages). Build the semantic model: `WAREHOUSE.fact_*` + `dim_*` relationships under the lean-marts pattern; disable autodetect on first load (Project #1 carry-forward). Build the Home page from `mart_executive_overview`.
2. **Session 5.2 — Demand by Hierarchy + Promotion & Price pages.** Two slicing pages off the warehouse star, plus their page-specific DAX measures.
3. **Session 5.3 — Seasonality & Calendar page + forecasting research.** Calendar-based page with weekend / holiday slicers via `dim_calendar`. Then research/decide the forecasting approach: Snowflake Cortex ML functions (most current, leans into the Snowflake stack) vs Python (statsmodels/Prophet, more portable). Lock the choice in this session.
4. **Session 5.4 — Build the forecasting layer end-to-end.** Train or invoke whatever's chosen in 5.3 → write results back to Snowflake → new `mart_forecast_vs_actual` dbt model joining forecasts to fact at sale_date grain, with appropriate tests. Verify SQL artefact `10_phase5_mart_forecast_vs_actual_verification.sql` follows the `04_`–`09_` pattern.
5. **Session 5.5 — Forecast vs Actual page + full DAX measure library.** Build the fifth page from the new mart. Round out the DAX measure library: time intelligence (YTD/QTD/MTD), period-over-period comparisons (YoY, vs forecast), dynamic top-N filtering, dynamic format strings.
6. **Session 5.6 — Cross-page drill-throughs + performance tuning + `POWERBI_PIPELINE.md` + closing audit.** Global slicers across pages, drill-through actions, theme polish via format painter, VertiPaq compression analysis, BI-side aggregations if needed. New `POWERBI_PIPELINE.md` walkthrough doc matching EXTRACT_PIPELINE / DBT_PIPELINE depth. 10-point + phase-boundary structural audits. Bundled commit + push closes Phase 5.

**Phase 6 — CI/CD + ship (2-3 sessions):**

1. **Session 6.1 — GitHub Actions CI fully wired.** `dbt parse` + `dbt test` on every PR + dbt slim CI (only changed models + downstream) + `sqlfluff` lint with project-specific rules + markdown lint. Green badge in README. Workflows live in `.github/workflows/`.
2. **Session 6.2 — `dbt docs generate` hosted on GitHub Pages + Power BI screenshots + README final polish.** `dbt docs serve` artefacts deployed via GitHub Pages action. All five Power BI page screenshots dropped into README. "How to run this" section populated with end-to-end setup. "Key learnings" section curated from LEARNINGS.md highlights.
3. **Session 6.3 — Final closing audits + v1.0 tag.** Project-wide 10-point + phase-boundary structural audit (catches anything that's drifted across the whole repo). Tag `v1.0` release, verify public repo on GitHub renders cleanly. **Project ships.**

---

**Last action (2026-05-17 — Phase 4 session 5):** Marts layer opened end-to-end under the lean-marts pattern. Direction-change decision logged in `LEARNINGS.md` → "2026-05-17 — Lean marts layer + analyst-facing star schema". `mart_executive_overview.sql` shipped — two-CTE shape (source → aggregated), `SUM(units_sold)` + `SUM(revenue_amount_usd)` + `CASE`-inside-`COUNT(DISTINCT)` for active item/store counts. 10 tests in `_marts__models.yml`: `unique`/`not_null` on `sale_date` PK, `not_null` + `accepted_range` on the four measures (`accepted_range` upper bounds 3,049 and 10 tied to M5 dim cardinalities — grain-safety nets). All tests use modern dbt 1.10+ `arguments:` syntax from the start — discipline rule from sessions 3+4 applied without re-encountering the deprecation. Targeted build `dbt build --select mart_executive_overview` → **PASS=11 in 7.56s**; subsequent full-DAG `dbt build --no-partial-parse` → **PASS=78 in 17.72s** end-to-end. Verify SQL `09_phase4_mart_executive_overview_verification.sql` — 6 sections + single-row PASS/FAIL rollup; ran section-by-section in Snowsight, **§6 → 4× PASS**. Aggregation parity verified at the SUM level (units 34,437,817 and revenue $93,559,341.40 both reconcile mart vs fact); active counts reconciled via re-computation from the fact for 2013-06-15 (mart 2,205 items / 10 stores = fact 2,205 / 10). **10-point code-quality audit**: 10 ✅ across all three new files. **Phase-boundary structural audit** (second explicit application): caught one real historical finding — PROJECT_CONTEXT session-4 record undercounted `fact_daily_sales` tests by 1 (model-level `unique_combination_of_columns` test was missed in the column-level tally). Corrected in this block; discipline rule going forward: count tests by reading the targeted `dbt build` output line, not by scanning the YAML. **`marts/.gitkeep` deleted** — stale scaffolding from session 1; folder now contains real model files. All four dbt model folders now scaffolding-free. **At session 5 open**: revised `PROJECT_PLAN.md` locking the lean-marts pattern (Architecture row in locked decisions, Phase 4 timeline row, "Power BI choking on raw fact" risk-register entry marked Superseded 2026-05-17). **At session 5 close**: locked Phase 4 session 6 (Airflow ↔ dbt wiring via Astronomer Cosmos) — Cosmos chosen over `BashOperator`/hybrid because each dbt model becomes its own Airflow task with full lineage in the UI; real-shop integration pattern; most professional for the targeted role-shape.

**Files added this session (Phase 4 session 5):**

- `dbt/models/marts/mart_executive_overview.sql` — first mart in the project. Two-CTE shape (source → aggregated). 28 lines, `materialized='table'`. 1,079 rows materialised in `RETAIL_DB.MARTS.MART_EXECUTIVE_OVERVIEW`.
- `dbt/models/marts/_marts__models.yml` — schema YAML for the mart. 10 tests across 5 columns. Modern dbt 1.10+ `arguments:` syntax on every namespaced test. Rich column descriptions explain the `not_null` reasoning on `total_revenue_usd` (aggregate of nullable fact column) and the `accepted_range` upper bounds tied to dim cardinalities.
- `sql/verify/09_phase4_mart_executive_overview_verification.sql` — durable verification artefact. 6 numbered sections + single-row PASS/FAIL rollup. Same pattern as `05_` through `08_`. Re-runnable from Snowsight any time.

**Files updated this session (Phase 4 session 5):**

- `LEARNINGS.md` — 4 new entries: Design Decision "2026-05-17 — Lean marts layer + analyst-facing star schema" (locked the architectural direction early in the session); Technical Learning "2026-05-17 — Mart-layer aggregation patterns" (SUM-NULL, CASE-inside-COUNT-DISTINCT, cardinality-tied `accepted_range`, `not_null`-on-aggregate-of-nullable); Mistakes & diagnoses entry "2026-05-17 — Test-count drift in PROJECT_CONTEXT records" (the +1 historical accounting finding from the structural audit); Design Decision "2026-05-17 — Extend Airflow DAG with dbt orchestration via Astronomer Cosmos" (locked Phase 4 session 6 plan).
- `DBT_PIPELINE.md` — added `mart_executive_overview` walkthrough section (~130 lines) matching the depth of `fact_daily_sales`. Six sub-sections (lean-marts call in one paragraph, shape with CTE structure, two SQL idioms, test design with cardinality-tied bounds, build outcome + ~30,500× compression headline, verification table). Header date bumped to 2026-05-17. "Sections to add as Phase 4 progresses" placeholder trimmed and renamed to "Sections to add (Phase 4 closeout)" — Marts bullet removed (covered); only the Airflow-orchestrating-dbt bullet remains, now pointing at session 6.
- `PROJECT_PLAN.md` — Architecture row in locked decisions updated to reference lean marts. Phase 4 timeline row description rewritten ("Marts layer (lean): `mart_executive_overview` only..."); Phase title renamed to "dbt transformations + orchestration"; session count bumped 3-4 → 5-6 (5 done, session 6 for Cosmos); deliverable row updated to "+ Airflow-orchestrated dbt build". Risk-register "Power BI choking on raw fact" entry marked **Superseded 2026-05-17**. Status block at bottom updated to Phase 4 session 5 closed / session 6 next.
- `PROJECT_CONTEXT.md` — this file. Header date + "Current phase" paragraph rewritten. New session-5 closeout block inserted above the session-4 block. Session-4 block left intact as historical record (its "Next session" plan for session 5 reads as the planning record of what we then executed).

**Files deleted this session (Phase 4 session 5):**

- `dbt/models/marts/.gitkeep` — stale scaffolding from Phase 4 session 1; folder now contains real model files (`mart_executive_overview.sql`, `_marts__models.yml`). All four dbt model folders are now scaffolding-free. Only `airflow/plugins/.gitkeep` remains in the repo, and that's a legitimate placeholder (folder genuinely empty pending plugin work).

**Headline outcomes from this session (Phase 4 session 5):**

- **Lean-marts architectural pattern locked.** Dropped from 5 marts to 1 (with `mart_forecast_vs_actual` deferred to Phase 5 if needed). The warehouse star (fact + dims) is now the primary analyst-facing surface; marts hold pre-aggregations only where they earn their keep. Most-professional default for the BI-Analyst / DE-adjacent role-shape Phil is targeting; gives Power BI real modelling work to demonstrate. Interview talk-track: *"I exposed the warehouse star directly to Power BI for analyst flexibility. The marts layer holds pre-aggregations only where they genuinely earn their keep."*
- **Marts layer live end-to-end.** `mart_executive_overview` shipped, tested (10 dbt tests + 6-section Snowsight verify, all PASS), and end-to-end-rebuilt in 17.72s. The dbt project now spans `RAW → STAGING → INTERMEDIATE → WAREHOUSE → MARTS` with full test coverage at every layer.
- **Aggregation compression — interview talk-track number.** 32,898,710 fact rows → 1,079 mart rows = **~30,500× compression**. Power BI home page reads 1,079 rows instead of 33M. *"I pre-aggregated 32.9M fact rows down to a 1,079-row daily summary, a ~30,500× compression that makes the dashboard home page instant in Power BI."*
- **Phase 4 session 6 (Airflow ↔ dbt wiring via Cosmos) locked.** Direction change captured mid-session: extending the existing DAG with `<Cosmos task group> → verify_dbt_one_day` tasks. Closes Phase 4 with the headline portfolio narrative — *the pipeline runs end-to-end on a schedule, with proper failure handling, tests, and per-model lineage visibility*.
- **Structural audit earned its keep again** on its second explicit application — caught the +1 test-count drift in PROJECT_CONTEXT records that would otherwise have propagated forward as a stale number.

**Next session (Phase 4 session 6) — Airflow ↔ dbt wiring via Astronomer Cosmos:**

1. **Pre-flight research** — read Cosmos docs to confirm installation steps in our existing Airflow stack (Docker image extension, `astronomer-cosmos` pip pin, profile/project mounting into the worker container).
2. **Install Cosmos** — add `astronomer-cosmos` to `airflow/requirements-airflow.txt` (or equivalent), rebuild the Airflow image, restart the stack. Verify with a one-line import test.
3. **Extend `m5_daily_extract.py`** — add a `DbtTaskGroup` (or equivalent Cosmos construct) downstream of `verify_one_day`. Each dbt model becomes its own Airflow task; the existing `dbt_project.yml` + `profiles.yml` get mounted into the worker. Confirm per-model task visibility in the Airflow UI's graph view.
4. **Add `verify_dbt_one_day` task** downstream of the Cosmos task group. Runs the §6 PASS/FAIL queries from `04_` / `04a_` / `05_` / `06_` / `07_` / `08_` / `09_*.sql` against Snowflake. Single Airflow task, multi-section query, RuntimeError on any FAIL — same pattern as the existing `verify_one_day`.
5. **End-to-end trigger** — manual UI-form trigger for one date. Observe all four stages fire green: extract → verify_extract → Cosmos-managed dbt models → verify_dbt. Confirm per-model dbt-task visibility in the Cosmos UI.
6. **Failure injection test** — deliberately break one dbt test (e.g., flip an `accepted_range` lower bound) and trigger; confirm `verify_dbt_one_day` does not fire (chain halts cleanly at the dbt-test failure).
7. **Doc updates** — DBT_PIPELINE.md gains a substantial "Airflow orchestration" section; PROJECT_PLAN / PROJECT_CONTEXT / LEARNINGS get session-6 closeout blocks. Per-script 10-point + phase-boundary structural audits applied.
8. **Bundled commit + push** — closes Phase 4 properly. Power BI opens next as Phase 5 session 1.

---

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

**Next session (Phase 4 session 5) — lean marts layer:**

Direction change locked at session 5 open: dropped the original 5-marts-one-per-page plan in favour of a **lean / analyst-facing star** pattern. Power BI consumes `WAREHOUSE.fact_*` + `dim_*` directly for slice/dice work; marts hold pre-aggregations only where they earn their keep. Full reasoning in `LEARNINGS.md` "2026-05-17 — Lean marts layer + analyst-facing star schema". Plan for this session:

1. **One mart only: `mart_executive_overview`.** Grain: one row per `sale_date`. Columns: `sale_date` (PK), `total_units_sold`, `total_revenue_usd`, `active_item_count`, `active_store_count`, `rows_in_grain` (diagnostic). NO denormalised date attributes — Power BI joins `dim_calendar` for those. Pre-aggregates 32.9M fact rows → ~1,148 daily rows for fast home-page refresh.
2. Materialised as `table` per `dbt_project.yml` marts default. No incremental needed at this volume.
3. Schema YAML — `unique` + `not_null` on `sale_date`; `accepted_range` on `total_units_sold` and `total_revenue_usd` (both `>= 0`).
4. Per-model verify SQL file `09_phase4_mart_executive_overview_verification.sql` — sections for upstream parity vs `fact_daily_sales`, PK uniqueness, measure-sanity (totals reconcile), 5-row eyeball, PASS/FAIL rollup.
5. Delete `dbt/models/marts/.gitkeep` once the mart lands.
6. `mart_forecast_vs_actual` deferred to Phase 5 (only built once forecasts exist; legitimate cross-domain mart).
7. End-of-phase structural audit + 10-point code-quality audit + doc updates (DBT_PIPELINE marts walkthrough section) + bundled commit. Closes Phase 4.

---

**Last action (2026-05-16 — Phase 4 session 3):** Opened intermediate + warehouse layers in one session.

- `dbt_utils 1.3.3` installed via `packages.yml` + `dbt deps`; `package-lock.yml` committed.
- First compound-key uniqueness test on `stg_m5_sell_prices` `(store_id, item_id, wm_yr_wk)`; caught dbt 1.10+ `MissingArgumentsPropertyInGenericTestDeprecation` mid-session — fixed via `arguments:` wrapping, flushed cache with `--no-partial-parse`.
- Built `int_sales_with_prices` (view) using `source → enriched → final` CTE pattern; LEFT JOIN to calendar + prices, computed `revenue_amount_usd`. 8 tests pass. Live-verified in Snowsight — 32.9M row parity, NULL-price rate 34.66% (M5 product lifecycle).
- Built `dim_calendar` (warehouse, **table**) — `dbt_utils.generate_surrogate_key(['calendar_date'])` for `date_key`. ISO date variants (`DAYOFWEEKISO`, `WEEKISO`) + `DAYNAME(...) IN ('Sat','Sun')` for session-parameter/convention independence. 1,079 rows, 11 tests. Distribution sanity confirmed weekend rate 28.64%, holiday rate 8.16%, 30 distinct event names. NULL-vs-empty-string trap caught implicitly via `is_holiday = FALSE` on event-less rows.
- 10-point audit: final 10 ✅ (sqlfluff still deferred to Phase 6). Anomaly check `units_sold > 0 AND sell_price IS NULL` returned 0 rows — validates LEFT JOIN as semantic design choice (preserves "on shelf, didn't sell" signal).
- Two per-model verify files added (`04_phase4_int_sales_with_prices_verification.sql`, `05_phase4_dim_calendar_verification.sql`).
- Parallel sub-agent built `GLOSSARY.md` — ~155 terms across 16 sections (~880 lines, `[Project 2]` tags for carry-forward). `TEACHING_PREFERENCES.md` gained one bullet: Snowsight diagnostics follow the one-query-per-code-block rule.

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

---

**Last action (2026-05-15 afternoon — Phase 4 session 2):** Built the staging layer end-to-end.

- Per-layer schema separation wired (custom `generate_schema_name` macro + `+schema:` per folder) — clean STAGING/INTERMEDIATE/WAREHOUSE/MARTS schemas instead of dbt's default concatenation.
- `sources.yml` with column docs + 36h/72h freshness thresholds; fixed dbt 1.11 `PropertyMovedToConfigDeprecation` by nesting under `config:`. All three sources PASS on `dbt source freshness`.
- Three staging models: `stg_m5_calendar` (flat — date cast, SNAP snake-case), `stg_m5_sell_prices` (9-line passthrough), `stg_m5_sales_train` (CTE pattern with LEFT JOIN to calendar for `d_NNNN` → real DATE). 14 tests including the `sale_date NOT NULL` join sentinel.
- **Real bug caught mid-session:** first `dbt build --select staging` failed with `Insufficient privileges to operate on database 'RETAIL_DB'` — role lacked `CREATE SCHEMA`. Diagnosed via `SHOW GRANTS`, fixed with new `sql/snowflake/03_grant_dbt_privileges.sql` (single GRANT), re-ran clean.
- 10-point audit: 8 ✅, 1 ⚠️ flagged for Phase 6 (sqlfluff), 1 ⚠️ closed in-session. Final state: `dbt build --select staging` → PASS=17 (3 views + 14 tests) in 4.5s.

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

---

**Last action (2026-05-15 — Phase 4 session 1):** Hand-scaffolded the dbt project (not `dbt init`) — every file deliberate.

- `dbt-snowflake 1.11.5` installed into existing `.venv` alongside Phase 3's Airflow stub; expected "multiple tools in one venv" pip warnings, all harmless (see LEARNINGS).
- Wrote `dbt/dbt_project.yml` and `dbt/profiles.yml` (clean professional versions; walkthrough in new `DBT_PIPELINE.md`).
- `.gitignore` got `!dbt/profiles.yml` exception (profile uses `env_var()`, safe to commit). `dbt debug` passes end-to-end.
- Mid-session `TEACHING_PREFERENCES.md` refinements: (a) comments-above-the-line never end-of-line (horizontal scroll breaks reading flow); (b) three-layer pattern for every code-shaped file — verbose-in-chat / clean-on-disk / walkthrough-md-alongside.

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

---

**Last action (2026-05-15 — Phase 3 session 2):** Added `verify_one_day` task downstream of `extract_one_day` in `m5_daily_extract`.

- Three independent Snowflake-side checks (CALENDAR = 1 row, SELL_PRICES > 0, SALES_TRAIN > 0) batched into one SQL round-trip.
- **Caught a real silent failure within 10 minutes of deployment** — today's `2026-05-15` auto-fire (no M5 data for that date) extracted 0 rows without error; verify queried Snowflake, found 0 rows, raised RuntimeError, task square went red. Pipeline correctly reported "data did not actually land."
- UI trigger form enabled via `AIRFLOW__WEBSERVER__SHOW_TRIGGER_FORM_IF_NO_PARAMS=true`; 20-minute UI gotcha around play-arrow vs `w/ config` buttons documented in LEARNINGS. Test trigger for `2014-01-04` via UI form: extract + verify both green end-to-end.

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
