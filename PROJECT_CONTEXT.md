# PROJECT_CONTEXT.md — Retail Demand & Forecasting Pipeline

> Project history + live state. Read this at the start of every Cowork session,
> alongside `TEACHING_PREFERENCES.md`.
> Last updated: 2026-05-22 (Phase 6 closed — v1.0 SHIPPED).

---

> **🎯 PROJECT STATUS — v1.0 SHIPPED 2026-05-22.**
>
> All six phases complete. End-to-end pipeline operational: Azure SQL → Snowflake `RAW` → dbt `STAGING` / `INTERMEDIATE` / `WAREHOUSE` / `MARTS` → Snowflake Cortex ML forecast → 5-page Power BI dashboard. Pipeline smoke-tested across 2 fresh dates at 5.9 close, all 4 tasks green end-to-end. Documentation + ship pass closed at Phase 6: README has 5 page screenshots + future-revival paragraph; POWERBI_PIPELINE.md is a 326-line walkthrough matching EXTRACT_PIPELINE / DBT_PIPELINE depth; CI workflows shipped (ruff F821 + dbt parse + sqlfluff). v1.0 git tag at Phase 6 close.
>
> **Carry-forward to Project #3 (Data Vault / streaming) — the rules and patterns that earned their keep across Phase 5-6:**
>
> - 1-2 steps per response on UI walkthroughs, no walls of text
> - Code blocks for paste-able only; plain text for read-not-copy
> - PowerShell: one command per code block
> - Airflow `schedule=None` for portfolio-demo DAGs (no auto-fire on unpause)
> - NEVER pause an Airflow DAG mid-run (sequence: unpause → trigger → complete → pause)
> - Scan ALL references when surgically removing a variable (success-path return f-strings are the easy-miss case)
> - PBI all-Import storage mode; measures live on `_Measures` hidden table; never aggregate raw mart columns from a fact-keyed measure
> - Snowflake unquoted identifiers stored as UPPERCASE — DAX must match catalog case
> - When 3 things look broken at once, suspect ONE root cause; try the cheapest single-variable fix first
> - PBI diagnostic order: Pause Visuals first, then close+reopen for cyclic refs, then trace the model
> - Transformation layer hierarchy: dbt → Power Query → DAX → visual (cleanup at lowest possible layer)
> - Feature-detect on screenshots before prescribing PBI UI clicks — variant differences matter
> - Default to "most professional"; lean teaching-heavy in conversation, ship clean code in commit
>
> Session opening directives from Phase 5 (5.8, 5.9) and Phase 6 have been retired — they were forward-looking instructions for sessions that have now closed. The session-by-session closeout blocks below remain as project history.

---

## Phase 6 closeout (2026-05-22)

**Headline outcomes:**

- **README Dashboard section populated end-to-end.** Five Power BI page screenshots captured at the 5.9 model state, saved to `powerbi/screenshots/` with lowercase-underscore filenames. Each embedded in README with a 1-2 sentence caption grounded in the visible screenshot content. One caption corrected mid-review when an initial draft claimed "Q4 seasonality" based on memory from the 5.6 closeout text; cross-checked against the actual Year × Month heatmap and found the data didn't support that claim (Oct-Dec values are not materially stronger than Mar-Jul for 2012/2013). Corrected to "year-on-year revenue growth (~50% lift from 2011 to 2013)" — accurate to the visual. Single-mistake protocol followed: flag the inaccuracy in chat, propose the fix, get OK, then apply. Forecast vs Actual screenshot re-snipped once because the Units chart had visible filter/expand chrome icons in its top-right corner (visual was selected when first snipped); deselected and re-saved cleanly.
- **POWERBI_PIPELINE.md rewritten from 5.4 stub to 326-line walkthrough.** Matches EXTRACT_PIPELINE / DBT_PIPELINE depth. Sections: headnote with the 5.9 close framing; architecture position; Snowflake connection deep-dive with both 5.1 gotchas (schema visibility ≠ access boundary; credential desync); storage mode arc (full Import → composite at 949 MB push limit → UDA detour → all-Import lean final); 6-table semantic model with relationship table and `_Measures` hidden table convention; 3 calc columns + 1 Power Query `Text.Proper` transformation; the five pages with full visual / polish / insight breakdown per page; 16-measure DAX library grouped by domain (base / page-specific / forecast / time-intel); cross-page UX (sync slicers, theme, drill-through ATTEMPTED+PULLED); VertiPaq Analyzer results from the 5.8 .vpax export; 19 polish discipline rules across 5 categories (diagnostic-order / architecture / format-pane / build-order / data-correctness); Phase 6 capture snapshot; future revival for interview demo; cross-references to all sibling docs.
- **README "Demo & future revival" paragraph added** between Dashboard and Key learnings. Tight ~2-paragraph summary pointing at POWERBI_PIPELINE.md for full detail. Covers: .pbix is Import-mode so opens standalone (data baked in); live refresh demo path is pay-as-you-go Snowflake Standard for one week the week before an interview (~$5 expected); end-to-end demo flow is trigger DAG → refresh PBI → show new row in Data view.
- **CI workflows shipped — 2 of 3 stretch items.** `.github/workflows/lint-python.yml` runs `ruff check --select F821 .` on PR + push to main, defense-in-depth against the 5.9 `mart_rows` NameError class of bug. `.github/workflows/dbt-ci.yml` runs `dbt parse` (catches Jinja/ref/source errors, no DB connection needed) + `sqlfluff lint models/` (Snowflake-dialect SQL style check) on PR + push when `dbt/**` changes. `dbt test` deliberately excluded from CI to avoid burning pay-as-you-go Snowflake credits on every push; comment in the workflow explains the call. `dbt/.sqlfluff` config file pins the dialect to snowflake, templater to jinja (no DB connection required for lint), uppercase keywords matching Phil's SQL style preference, 120-char line length, 3 rule exclusions documented inline (LT05 line length, RF02 qualified references, ST05 subquery rewrites). Dummy env vars in dbt-ci.yml so dbt parse templates valid strings without needing real Snowflake creds.
- **VertiPaq dim-cardinality stretch CUT.** `.vpax` files use ZIP64 archive format which Windows native `Expand-Archive` cannot read (errors with "Offset to Central Directory cannot be held in an Int64"). Could be worked around with 7-zip or `python -m zipfile`, but the value-vs-effort ratio doesn't justify the additional 20-30 minutes given the high-level VertiPaq stats from 5.8 are already documented in POWERBI_PIPELINE.md §11 (~254 MB compressed, FACT 67%, forecast 25%, ~5 bytes/row/col compression). The .vpax file itself ships with the repo so any future reviewer with DAX Studio can open it for the per-column drill-down. Honest "cut, don't gold-plate" decision.
- **All 13 markdown files swept** for v1.0 close. PROJECT_PLAN.md Status block compressed from a 5-paragraph 5.9-and-earlier closeout into a tight Phase 6 close paragraph (duplicated history removed; lives in PROJECT_CONTEXT.md). PROJECT_CONTEXT.md header updated, retired Phase 6 + 5.8 opening directives, this closeout block prepended above 5.9 closeout. LEARNINGS.md, POWERBI_PLAYBOOK.md, LEARNING_ROADMAP.md, GLOSSARY.md, CODE_QUALITY.md, README.md Key learnings stub — all updated.

**Files updated this session (Phase 6):**

- `README.md` — Dashboard section populated with 5 PBI page screenshots + grounded captions; "Demo & future revival" section added between Dashboard and Key learnings; Key learnings stub populated.
- `POWERBI_PIPELINE.md` — full rewrite from 214-line stale stub to 326-line v1.0 walkthrough. See headline outcomes for detail.
- `PROJECT_PLAN.md` — Status block compressed to Phase 6 close summary; Next step set to "Project complete — begin Project #3".
- `PROJECT_CONTEXT.md` — this file. Header bumped to Phase 6 closed / v1.0 SHIPPED; Phase 6 opening directive + 5.8 opening directive retired; v1.0 STATUS banner replaces them; this Phase 6 closeout block prepended above 5.9.
- `LEARNINGS.md` — 2 new Phase 6 entries appended: (a) .vpax ZIP64 format incompatibility with Windows Expand-Archive (workaround paths documented); (b) ruff F821 as CI defense-in-depth pattern for stale-variable-reference bugs surfaced from the 5.9 mart_rows incident.
- `POWERBI_PLAYBOOK.md` — Phase E status mark complete; trailing notes scrubbed of Phase-6-pending references.
- `LEARNING_ROADMAP.md` — Phase 5 + Phase 6 marked complete; project marked v1.0 SHIPPED.
- `GLOSSARY.md` — 4 new terms added (CI / GitHub Actions; ruff + F821; sqlfluff; .vpax + VertiPaq Analyzer).
- `CODE_QUALITY.md` — Phase 6 audit results appended (3 new CI files all pass 10-criteria checklist).
- `.github/workflows/lint-python.yml` — new, Python F821 lint CI.
- `.github/workflows/dbt-ci.yml` — new, dbt parse + sqlfluff lint CI.
- `dbt/.sqlfluff` — new, Snowflake-dialect lint config.
- `powerbi/screenshots/executive_overview.png` — new (260 KB).
- `powerbi/screenshots/demand_by_hierarchy.png` — new (111 KB).
- `powerbi/screenshots/promotion_and_price.png` — new (72 KB).
- `powerbi/screenshots/seasonality_and_calendar.png` — new (127 KB).
- `powerbi/screenshots/forecast_vs_actual.png` — new (122 KB), one re-snip after deselecting chrome icons.

**Pending / deferred to Project #3 (none for this project — v1.0 is complete):**

- VertiPaq per-dim per-column cardinality drill-down (ZIP64 + DAX Studio install path issue; .vpax ships for any future reviewer with DAX Studio).
- Reinstall DAX Studio as "Install for all users" for External Tools ribbon registration — only relevant if Phil returns to PBI work on this project.

---

## Session 5.9 closeout (2026-05-22)

**Headline outcomes:**

- **End-to-end DAG smoke test executed successfully** for two consecutive dates after a multi-stage debug. Triggered `m5_daily_extract` for logical_date 2014-03-24 (Run ID `smoke_test_5_9_2014_03_24`). First three tasks (`extract_one_day`, `verify_one_day`, `dbt_models` task group with all 14 sub-tasks) ran green; `verify_dbt_one_day` failed with `NameError: name 'mart_rows' is not defined`. Diagnosed the bug in airflow/dags/m5_daily_extract.py line 379 — the success-path f-string return statement still referenced `mart_rows`, a variable that had been removed from the SQL/binds/unpack/log/check blocks back in Phase 5.4 when the mart-layer check was deleted, but the return string was missed in the surgical removal. Fix shipped (removed `, mart={mart_rows}` from the f-string). Re-triggered for logical_date 2014-03-25 (Run ID `smoke_test_5_9_2014_03_25_test_run_2`); all 4 tasks went green end-to-end. PBI sanity verification: opened .pbix, Home → Refresh, Data view → FACT_DAILY_SALES (View hidden enabled) → sorted SALE_DATE descending; top row = Tuesday, 25 March 2014. Pipeline confirmed healthy across all 4 layers (extract → verify → dbt → verify_dbt) and end-to-end data lineage from Azure SQL → Snowflake RAW → STAGING → INTERMEDIATE → WAREHOUSE → MARTS → PBI Import-mode semantic model.
- **DAG architectural fix: `schedule="@daily"` → `schedule=None`.** Discovered mid-session that unpausing the DAG (to recover from a pause-mid-run trap — see below) immediately spawned a phantom DagRun for the most recent missed scheduled interval (~2026-05-22), which tried to extract M5 data for today's date from Azure SQL (no data past 2016) and failed. Phil flagged this as a design fault: for a portfolio-demo DAG, the operator should explicitly control every DagRun via "Trigger DAG w/ config"; auto-firing on unpause is the wrong default. Changed the `@dag` decorator's `schedule="@daily"` → `schedule=None` (kept `catchup=False` as belt-and-braces). Docstring + inline comment updated to document the 5.9 decision and pattern reasoning. Verified post-change: triggering for 2014-03-25 + leaving DAG unpaused through completion no longer spawns phantom runs. Interview talk-track strengthened: "schedule=None so the operator controls every run explicitly; date-partitioned extract pattern works because each DagRun gets a logical_date via config, and the extract task reads `context['ds']` to pull the right slice."
- **3 new durable LEARNINGS banked, all Airflow-domain, all portable to Project #3.** (a) **Airflow `schedule=None` is the correct pattern for portfolio-demo DAGs** — explicit-trigger-only, no phantom runs, no unpause-time auto-firing. (b) **Airflow pause-mid-run trap** — paused DAGs strand tasks in "scheduled" state because the scheduler refuses to push them to "queued"; symptom is task sitting on "scheduled" for >2 minutes (well outside the normal 5-30s transition window); fix is unpause; discipline rule is NEVER pause a DAG mid-run, sequence is always "unpause → trigger → let it complete → THEN pause". (c) **Stale variable references in surgically-modified functions** — when removing a check or variable from a function, scan ALL references: SQL query, bind tuple, unpack line, log calls, **success-path return string/f-string**, failure-check block. Success-path return is the easy-to-miss case because it only executes on the happy path — exactly the path that hasn't been exercised since the modification. Defense-in-depth: add `ruff` with `F821` (undefined-name) to CI as pre-merge gate in Project #3.
- **POWERBI_PLAYBOOK.md UDA-reference scrub.** Three surgical edits to scrub stale references to user-defined aggregations (UDA was abandoned in Phase 5.4 due to all-Import storage incompatibility, but stale references survived in the playbook): (a) §1.1 storage-mode table — removed the 2 AGG rows (AGG_SALES_DAILY, AGG_SALES_DAILY_ITEM_CAT) since they're not in the PBI model; (b) §6 Phase C checklist — updated "Get Data → Select" line to drop the 2 AGG tables from the table selection with inline footnote pointing at §1.4; (c) §6 Phase C checklist — Manage Aggregations step marked SUPERSEDED with strikethrough + footnote; Hide step updated to drop AGG references. agg_sales_daily.sql and agg_sales_daily_item_cat.sql retained in dbt/models/marts/ as portfolio-narrative artefacts ("I built two pre-aggregated marts following the Kimball aggregate pattern, then learned UDA requires DirectQuery on the detail table — incompatible with all-Import — so kept the marts for the architectural story but didn't wire them into PBI"). Adds ~5-10 seconds to dbt build, negligible cost for the talk-track value.
- **One phantom DagRun retained in Airflow run history** for portfolio narrative. The 2026-05-22 DagRun that auto-spawned during the pause-mid-run recovery (before the schedule=None fix was deployed) is kept as a visible red square in the DAG's run history. Phil's decision: keeps the "found a bug during smoke testing, diagnosed it, fixed the design, demonstrated the fix" narrative legible in the UI rather than scrubbing the evidence. Future-Claude reading this repo for interview-prep talk-track has the visible artefact to reference.

**Files updated this session (Phase 5 session 5.9):**

- `airflow/dags/m5_daily_extract.py` — 3 code edits: (a) module docstring schedule line updated from `@daily` to `None` with 5.9 context note; (b) `@dag` decorator `schedule="@daily"` → `schedule=None` with 7-line inline comment explaining the 5.9 design decision and pattern reasoning; (c) `verify_dbt_one_day` return f-string — removed dangling `, mart={mart_rows}` reference (the 5.4 surgical-removal miss).
- `LEARNINGS.md` — 3 new entries appended to the Airflow section (just before the Power BI section header) covering schedule=None pattern, pause-mid-run trap, stale variable references in surgically-modified functions.
- `POWERBI_PLAYBOOK.md` — 3 surgical edits scrubbing stale UDA references from §1.1 storage-mode table and §6 Phase C checklist (see headline outcomes above for detail).
- `PROJECT_CONTEXT.md` — this file. 5.9 opening directive replaced with a Phase 6 opening directive carrying forward all 5.4-5.8 discipline rules plus the 3 new 5.9 ones; 5.9 closeout block inserted above the 5.8 closeout block.
- `PROJECT_PLAN.md` — Status block bumped (5.8 closed; 5.9 closed; Phase 6 next — README screenshots of all 5 PBI pages + POWERBI_PIPELINE.md walkthrough fill-in for sessions 5.2-5.8 + final commit/tag).
- `powerbi/retail_demand_forecasting.pbix` — refreshed + saved in-session (Home → Refresh pulled in the new rows for 2014-03-24 and 2014-03-25 from Snowflake; saved to disk so the .pbix snapshot now reflects the 5.9 data state). No model-level changes (no measure / relationship / page edits); the only delta vs 5.8 close is the cached imported data. Confirms end-to-end pipeline freshness: Azure SQL data for 2014-03-25 is now visible in the .pbix's Data view → FACT_DAILY_SALES → SALE_DATE descending → top row Tuesday 25 March 2014.

**Pending / deferred to Phase 6:**

- README update with screenshots of all 5 PBI pages (Executive Overview, Demand by Hierarchy, Promotion & Price, Seasonality & Calendar, Forecast vs Actual).
- POWERBI_PIPELINE.md fill-in for sessions 5.2-5.8 (the walkthrough doc that mirrors EXTRACT_PIPELINE / DBT_PIPELINE depth — currently a stub).
- README "Future-revival of Snowflake for interview demo" section — short paragraph explaining: .pbix is Import-mode so dashboard demos run standalone with data baked into the file; if a live refresh demo is needed for an interview 30+ days out (after Snowflake trial expiry), pay-as-you-go on Snowflake Standard tier for one week (~$5) the week before. New ask from Phil mid-session 5.9, to ensure future-Phil reading this repo in 2-3 years has the demo-revival story documented.
- VertiPaq Analyzer dim-cardinality check (deferred from 5.8 + 5.9 — DAX Studio per-user install path issue + standalone launch path now documented in 5.8 LEARNING).
- Optional: `ruff` with `F821` lint check as CI pre-merge gate (defense-in-depth from the 5.9 stale-reference LEARNING).
- Final commit + tag `v1.0` release at Phase 6 close.

---

## Session 5.8 closeout (2026-05-22)

**Headline outcomes:**

- **5-page polish pass complete end-to-end.** Seasonality & Calendar and Forecast vs Actual moved from "polish-deferred" to "interview-grade", joining the 3 pages shipped in 5.7. Project's BI deliverable is now portfolio-quality across all 5 pages with consistent theme, design language, and interaction patterns.
- **Seasonality & Calendar polish.** New `Day Type` calc column added to DIM_CALENDAR (`Day Type = IF(DIM_CALENDAR[IS_WEEKEND], "Weekend", "Weekday")`) replacing the raw boolean axis labels on the Weekday/Weekend column chart. Existing `is_snap_day` calc column on DIM_CALENDAR rewritten in place to `SNAP Day Type` returning text strings ("SNAP Day" / "Non-SNAP Day") instead of TRUE/FALSE — eliminates intermediate boolean step and simplifies the donut Legend on Promotion & Price. Three visuals on Seasonality renamed via General → Title (Revenue: Weekday vs Weekend; Revenue Impact by Holiday Event; Monthly Revenue by Year). Weekday chart: Weekend warm callout color, Weekday grey baseline, Y-axis off + gridlines off (data labels carry the story). Holiday bars: Top N = 10 filter via Filter pane on visual, X-axis off, $-formatted data labels via measure-level Format = Currency on Holiday Revenue. Heatmap matrix: green single-color sequential gradient via Cell elements → fx → Format style Gradient; "How should we format empty values?" set to Don't format killing the 2014 Apr-Dec red distortion; "Apply to = Values only" excluding the Total column/row from the gradient; Grow to fit via Layout → Column width → Auto-size behavior + Custom widths Off; Row padding bumped to 10 in Grid → Options; Global font size 11. All gridlines width 0 to fill matrix solidly. Title "Monthly Revenue by Year".
- **Forecast vs Actual polish + finish.** Forecast Units companion KPI card duplicated from Forecast Revenue card; both cards now mirror at top-right. Forecast Revenue measure already had Format = Currency (propagated to "$2.89M" automatically). Both line charts retitled: "Revenue: Actual vs Forecast" and "Units: Actual vs Forecast". Per-series styling via Format → Visual → Lines → Apply settings to: Actual = solid green; Forecast = dashed warm red; Upper 95 = dotted dark blue; Lower 95 = dotted pale grey. Date slicer un-synced from cross-page Date sync via View → Sync slicers panel (uncheck Sync for Forecast vs Actual row, keep Visible) — allows zoom to last 90 days (1/01/2014 → 22/05/2014) showing forecast horizon clearly without affecting other 4 pages' synced Date selections. Matrix at bottom: SERIES_TYPE values renamed via Power Query → Replace Values (actual → Actual, forecast → Forecast); measure column headers renamed via right-click Rename for this visual to drop "(Mart)" suffix (Total Units (Mart) → Units, Total Revenue (Mart) → Revenue) while keeping the (Mart) documentation on the underlying measures in _Measures; Layout → Column width → Custom widths Off; Grid → Options Row padding 10 / Global font size 11; Alternate background color set to No fill killing the row banding. Matrix title "Actual vs Forecast by Category".
- **Drill-through attempted + PULLED from 5.8 scope.** Item Detail destination page built (Card showing item_id + Table with calendar_date / store_id / state_id / Total Units Sold / Total Revenue), drill-through field well wired with DIM_ITEM[ITEM_ID] + "Allow drill through when = Used as category" + Keep all filters Off, page hidden. Right-click trigger from source visuals (tested on Top 10 Items table on Demand by Hierarchy) **did not fire** — context menu showed standard Copy/Show as table/Include/Exclude items but no "Drill through" option. Diagnostics attempted: save + close + reopen, lineage tooltip confirmation (DIM_ITEM[ITEM_ID] in both source and destination), Page type dropdown check (NOT exposed in this user's variant — Page information section only showed Set as landing page / Allow use as tooltip / Allow Q&A, no Drillthrough toggle). The community-cited #1 fix (Page type = Drillthrough) doesn't apply because the toggle doesn't exist in this variant. Cost-benefit decision: pull rather than continue chasing a variant-specific UI issue. **Item Detail page deleted.** PBI's automatic cross-filtering retains as the page-level interactivity story.
- **Theme cohesion verified across 5 pages.** City Park theme applied uniformly. Cat_id palette (FOODS blue / HOBBIES purple / HOUSEHOLD green) consistent across Demand by Hierarchy and Promotion & Price. Design language locked: warm red as event/forecast/over-index callout (Weekend, SNAP Day, Holiday bars, Forecast lines); grey as neutral baseline (Weekday, Non-SNAP Day); green as sequential heat (heatmap gradient + Actual series in Forecast charts); blue/purple/green as categorical (cat_id). Single consistent design rule across pages.
- **VertiPaq Analyzer deferred to 5.9.** DAX Studio (latest, 3.5.2) installed during 5.8 with "Install for me only" + Register as External Tool ticked. Reopened PBI Desktop — External Tools ribbon tab did NOT appear. Per-user install path places `daxstudio.pbitool.json` in `%LOCALAPPDATA%\DAX Studio\` instead of the all-users path PBI Desktop scans (`C:\Program Files (x86)\Common Files\Microsoft Shared\Power BI Desktop\External Tools\`). Documented as a LEARNING; rolls to 5.9 where Phil will either reinstall as "all users" or launch DAX Studio standalone via Start Menu and connect via the Connect dialog's Power BI / SSDT Model radio button.
- **One mid-session cyclic reference incident — clarified two-cause pattern.** After Phil ran Power Query Replace Values on MART_FORECAST_VS_ACTUAL.SERIES_TYPE, a refresh threw "A cyclic reference was encountered during evaluation" on DIM_ITEM and DIM_STORE. Initial 5.5-pattern close+reopen attempted. Investigation into Power Query M-code on MART_FORECAST_VS_ACTUAL confirmed Replace Values steps were correctly chained (first arg = `#"Navigation 3"` → `#"Replaced Value"` → `#"Replaced Value1"`, not self-referencing the query name). Determined the 5.5 spurious-cache pattern applied here too; close+reopen ultimately cleared it. LEARNING updated to capture the two-cause refinement: cyclic ref can be (a) spurious cache (close+reopen fix) OR (b) real M-code self-reference (formula bar inspection fix); diagnostic order is (a) first then (b).
- **6 durable LEARNINGS captured.** (a) Power BI Desktop format pane control locations vary heavily by variant — pin EXACT paths for matrix Row padding (Grid → Options), matrix Grow to fit (Layout → Column width), conditional formatting (Cell elements → Apply settings to → fx), new Card visual Value field well (NOT Fields). (b) PBI build order discipline: apply theme + test drill-through EARLY with 1-2 visuals, BEFORE polish — theme propagation reorganizes formatted visuals; failed drill-through trigger fix often requires delete + re-add of source visual. (c) PBI Desktop drill-through right-click trigger silently failing despite spec-correct wiring — variant-specific UI issue, unresolved diagnosis; recommend treating drill-through as nice-to-have polish with hard time-cap, pull from scope rather than burn hours. (d) PBI cyclic reference two-cause refinement to 5.5 LEARNING: spurious cache (close+reopen) vs real M-code self-reference (PQ formula bar inspection); diagnostic order. (e) Power Query Replace Values is the only stock-Desktop path for renaming categorical column values; in-visual rename works only for measure pills, not category values driving column headers. (f) DAX Studio External Tools registration requires "Install for all users" — per-user install path places pbitool.json in non-scanned location; ribbon tab won't appear.

**Files updated this session (Phase 5 session 5.8):**

- `LEARNINGS.md` — 6 new entries appended to the Power BI section covering all the items captured above.
- `PROJECT_CONTEXT.md` — this file. Header date bumped to 2026-05-22; 5.8 opening directive replaced with 5.9 opening directive carrying forward all discipline rules from 5.4-5.7 plus the 5 new 5.8 rules; 5.8 closeout block inserted above the 5.7 closeout.
- `PROJECT_PLAN.md` — Status block bumped (5.7 closed; 5.8 closed; 5.9 next — VertiPaq + DAG smoke test + delete unused measures + bundled commit; then Phase 6 README + POWERBI_PIPELINE walkthrough).
- `POWERBI_PLAYBOOK.md` — Phase E polish checklist updated: cross-page slicer sync ✅ (all 5 pages by 5.7 + Forecast vs Actual Date un-synced in 5.8); Theme polish ✅ (City Park applied across 5 pages, design language locked); Seasonality & Calendar polish ✅ (5.8); Forecast vs Actual polish ✅ (5.8); Drill-through ATTEMPTED + PULLED (5.8 — variant-specific UI failure, Item Detail page deleted); VertiPaq Analyzer deferred (5.8 → 5.9 — DAX Studio per-user install path didn't register External Tools).
- `powerbi/retail_demand_forecasting.pbix` — saved. 5 polished pages, **16 measures** on _Measures (20 before deletions; 4 unused speculative time-intel measures removed: Revenue PY / Revenue YoY $ / Revenue YoY % / Revenue YTD — all created for YoY indicator + YTD pill patterns that were skipped due to Reference labels missing on new Card visual variant), **2 calc columns on DIM_CALENDAR** (Day Type for readable Weekday/Weekend X-axis labels; SNAP Day Type — rewrite of original is_snap_day calc column returning "SNAP Day" / "Non-SNAP Day" text), **1 Power Query transformation** on MART_FORECAST_VS_ACTUAL.SERIES_TYPE (consolidated from 2 Replace Values steps to 1 Capitalize Each Word step using Text.Proper — cleaner M code). Page count: 5 (Item Detail deleted).
- `powerbi/retail_demand_forecasting.vpax` — new VertiPaq Analyzer export saved during 5.8 (76 KB). Captures per-column cardinality + dictionary size + encoding type + table sizes at session close. Interview talk-track artifact for portfolio narrative on model size + compression efficiency. Total compressed model size ~254 MB; FACT_DAILY_SALES at 35M rows / 67% of model; forecast layer 25%; columnar compression ~5 bytes/row/col average.

**Pending / deferred to session 5.9 (and Phase 6):**

- VertiPaq Analyzer dim-cardinality check (5.9 — DAX Studio install fix OR standalone launch + Connect dialog path).
- End-to-end DAG smoke test (single date, fresh) before Phase 6 close.
- Delete unused measures (final scan once 5.9 work confirms which measures still bind to visuals/tooltips).
- End-of-session bundled commit + push for 5.8 .pbix state + any 5.9 work.
- README update with screenshots of all 5 PBI pages (Phase 6).
- POWERBI_PIPELINE.md fill-in for sessions 5.2-5.8 (Phase 6).

---

## Session 5.7 closeout (2026-05-21)

**Headline outcomes:**

- **3 of 5 pages polished end-to-end.** Executive Overview, Demand by Hierarchy, and Promotion & Price all moved from "functional with default formatting" to "interview-grade" through one focused polish session. City Park theme applied; per-page formatting work documented below. Seasonality & Calendar and Forecast vs Actual still need their polish pass (slicers compacted on both during session breaks; visual formatting deferred to 5.8).
- **Cross-page slicer sync established.** View → Sync slicers panel used to propagate Date + Category slicers across all 5 pages so user filter selections persist as they navigate. State slicer not synced to Forecast vs Actual (forecast trained at item-level grain; State slicer not on that page by design).
- **Executive Overview polish.** City Park built-in PBI theme applied. 4 KPI cards repositioned into a single compact row with shortened labels (Revenue / Units Sold / Stores / SKUs) and renamed callout values. Active Items card switched from "3K" to "3,049" via Format → General → Data format → Whole number (the new-Card-visual "Display units" control is buried under field-level "Apply settings to specific measure" in the Nov 2025 redesign — required a web-doc check mid-session). Revenue 30-Day MA measure added as a dashed black overlay on the trend chart with per-series color override (the theme initially threw the chart's existing series colors off; reverted via Format → Visual → Lines → Colors). Tooltip $ formatting confirmed by setting Total Revenue's Format = Currency at measure level — propagated to every chart and tooltip using it.
- **Demand by Hierarchy polish.** 4 visuals arranged in clean 2×2 grid with ~20px gaps (top row: 2 bar charts at H=260 W=600; bottom row: matrix W=720 + table W=500 to fit the matrix's wider %GT Revenue Share column without overlap). Category-keyed bar colors via Color → fx → Format style Rules, basing on CAT_ID with operator `contains` and 3 rules: FOODS → dark blue, HOUSEHOLD → green, HOBBIES → red. Matrix "%GT Revenue Share" column header prefix stripped via right-click on field in Values well → Show value as → No calculation. All 4 visual titles renamed to natural English (Revenue by Category / Revenue by Department / Category Hierarchy Breakdown / Top 10 Items by Revenue).
- **Promotion & Price polish.** Avg Selling Price clustered column chart category-colored via Format → Visual → **Columns** (not Bars — vertical column charts use the Columns section in the new format pane) → Color → fx → same Rules pattern as Demand by Hierarchy. Y-axis switched to currency $0.00 / $2.00 / $4.00 / $6.00 via measure-level Format = Currency (Measure tools ribbon) on Avg Selling Price. Donut retitled "Revenue: SNAP vs Non-SNAP Days"; Detail labels → Label contents = `Category, percent of total`, Position = Outside; slice colors moved off green/red default to City Park blue/purple via Format → Visual → Slices → Colors. Scatter retitled "Price vs Revenue by Department"; bubble Size bound to Total Revenue; per-series marker colors set via Format → Visual → Markers → Apply settings to dropdown → pick FOODS/HOBBIES/HOUSEHOLD individually; custom marker shapes per category (triangle/diamond/circle) set the same way. X-axis padded to Start=2 End=6.5 to stop dots clipping at edges. Scatter legend reorder skipped — would require model-level Sort by column on CAT_ID (right-click CAT_ID → Sort by column → custom sort col), affecting every visual where CAT_ID is alphabetically sorted; trade-off not worth it for cosmetic legend ordering.
- **Two durable LEARNINGS captured.** (a) PBI format pane section names vary by visual type — Bars (horizontal bar) vs Columns (vertical column) vs Markers (scatter, with per-series Apply settings to dropdown) vs Slices (donut/pie). The "Colors" subsection sits inside different parent sections depending on visual type; don't assume uniformity. Cost ~10 min mid-session on the column chart before Phil corrected me. (b) New Card visual (Nov 2025 GA) Reference labels field well is missing in the basic-license / stock-standard Power BI Desktop variant — only Value / Categories / Tooltips / Drill through are exposed. Blocks the YoY % indicator pattern that relies on reference labels for the secondary value; YoY measure can still be used in tooltips, but the visual pattern isn't deliverable on this variant. Feature-detect on a screenshot before recommending Reference-labels-based patterns.
- **Format fixes from 5.6 backlog burned down.** Revenue Share % → percentage format ✅. Forecast vs Actual slicer compaction (Date 70×350, CAT_ID tile 70×340) ✅. Scatter bubble Size field bound to Total Revenue ✅. Orphan Measure on DIM_CALENDAR check ✅ (already clean — no orphan). Dashed/dotted line styling on Forecast / Upper 95 / Lower 95 series — deferred to 5.8 with the Forecast vs Actual full polish pass.
- **One new measure used; one experimental indicator skipped.** Revenue 30-Day MA placed on Exec Overview trend chart (added in 5.6, used for the first time in 5.7). YoY % indicator pill skipped due to the Reference labels limitation above; measure retained on `_Measures` for tooltip use.

**Files updated this session (Phase 5 session 5.7):**

- `LEARNINGS.md` — 2 new entries appended to the Power BI section: (a) PBI format pane section names vary by visual type — Bars / Columns / Markers / Slices with web-check discipline; (b) New Card visual Reference labels field well variant-dependent — feature-detect before recommending YoY/PoP indicator patterns.
- `PROJECT_CONTEXT.md` — this file. Header date bumped; 5.7 opening directive replaced with 5.8 opening directive carrying forward all discipline rules from 5.4-5.6 plus the 2 new 5.7 rules; 5.7 closeout block inserted above the 5.6 closeout.
- `PROJECT_PLAN.md` — Status block bumped (5.6 closed; 5.7 closed; 5.8 next — finish remaining 2 pages + drill-through + VertiPaq + DAG smoke test + bundled commit).
- `POWERBI_PLAYBOOK.md` — Phase E polish checklist updated: cross-page slicer sync ✅ (Date + Category across 5 pages), theme polish partial (City Park applied + 3 of 5 pages styled end-to-end), drill-through + VertiPaq + audit pending.
- `powerbi/retail_demand_forecasting.pbix` — saved. All 5 pages have full visual builds; 3 of 5 now fully polished. Measure count unchanged: 20 measures + 1 calculated column on DIM_CALENDAR (`is_snap_day`).

**Pending / deferred to session 5.8:**

- Seasonality & Calendar — full polish pass (slicers already compact; need theme cohesion + visual coloring + title renames + heatmap cosmetic polish).
- Forecast vs Actual — finish (KPI card pair completion + optional Forecast Units card duplicate + line chart spacing + dashed/dotted line styling on Forecast / Upper 95 / Lower 95 + matrix cosmetic polish + theme cohesion).
- Drill-through actions (Demand by Hierarchy → Item Detail; Promotion & Price → Item Detail).
- Theme consistency check across all 5 pages.
- VertiPaq Analyzer check on dim cardinalities (interview talk-track artifact).
- End-to-end DAG smoke test (single date) before final Phase 6 close.
- Delete unused measures once 5.8 polish is complete (Phil flagged at end of 5.6).
- README update with screenshots of all 5 PBI pages (Phase 6).
- POWERBI_PIPELINE.md fill-in for sessions 5.2-5.7 (Phase 6).

---

## Session 5.6 closeout (2026-05-21)

**Headline outcomes:**

- **All 4 remaining PBI page builds shipped in one session.** Demand by Hierarchy got its 2 bar charts (Revenue by Category, Revenue by Department) + Hierarchy matrix (cat → dept → item with Total Revenue + Total Units Sold + Revenue Share %) + Top 10 items by revenue table. Promotion & Price got its 3 slicers (copied from Demand by Hierarchy with sync slicers enabled), new `is_snap_day` calculated column on DIM_CALENDAR, Avg Selling Price by Category column chart, Revenue by SNAP Day donut, and Revenue vs Avg Price scatter (bubble per dept_id, colored by cat_id). Seasonality & Calendar got Weekend vs Weekday bar, Year × Month heatmap matrix (with YEAR data-type fix from Decimal → Whole number and MONTH_NAME sort-by-MONTH fix), and Holiday event impact bar. Forecast vs Actual got Date + Category slicers (no State — forecast trained item-level grain), 2 new mart-source measures (`Total Units (Mart)`, `Total Revenue (Mart)`) to make the matrix series_type column split work, Revenue line chart (Actual + Forecast over observation_date), Units line chart with 4 series (Actual + Forecast + Upper 95 + Lower 95 as CI bands), and cat × series_type matrix.
- **Three durable LEARNINGS captured.** (a) PBI calculated COLUMN vs MEASURE — same formula bar, different evaluation context. The "Cannot find name [column]" error on a verifiable column is the canonical symptom of clicking New measure when you wanted New column. Cost ~10 min mid-session before the right ribbon button was clicked. (b) Snowflake unquoted identifiers stored as UPPERCASE carry through to PBI column names — lowercase dbt source code → uppercase Snowflake catalog → uppercase PBI columns. DAX is case-insensitive for references but bare names still need to match the catalog. (c) `(Mart)` measure naming pattern — when same metric lives on two source tables (fact-sourced and mart-sourced), suffix the mart-sourced version `(Mart)` rather than renaming the original. The suffix is self-documenting and lets the field list show them side-by-side alphabetically.
- **Portfolio-grade insights surfaced by the new pages.** (a) SNAP days = 52.19% of revenue ($52.56M of $100.70M) — strong correlation between SNAP benefits distribution days and shopping behaviour. (b) Weekend per-day revenue exceeds weekday per-day: 35M / 2 weekend days = $17.5M/day vs 66M / 5 weekday days = $13.2M/day. Weekend over-indexes ~33%. (c) Top 10 items concentrate only ~5.7% of total revenue ($5.74M of $100.70M) — confirms classic retail long-tail distribution. (d) Year × Month heatmap reveals clean YoY growth + Q4 seasonality (October/November consistently strongest, January consistently weakest, Q4 column intensity increases each year). (e) Scatter shows FOODS_3 as cheap-price/high-volume outlier (~$2.80 avg / $40M revenue) — classic price-elasticity story.
- **Two new DAX measures added** to `_Measures`: `Total Units (Mart) = SUM(MART_FORECAST_VS_ACTUAL[UNITS])` and `Total Revenue (Mart) = SUM(MART_FORECAST_VS_ACTUAL[REVENUE_USD])`. Required for the Forecast vs Actual matrix because the existing fact-sourced measures can't be filtered by series_type (no path from MART_FORECAST_VS_ACTUAL.series_type to FACT_DAILY_SALES).
- **One new calculated column** added to `DIM_CALENDAR`: `is_snap_day = IF(DIM_CALENDAR[SNAP_CA]=1 || DIM_CALENDAR[SNAP_TX]=1 || DIM_CALENDAR[SNAP_WI]=1, TRUE, FALSE)`. Powers the Revenue by SNAP Day donut on Promotion & Price page.
- **Cross-session DAG/forecast layer remained verified.** No data layer touched this session — pure PBI work. The 7-section forecast layer verification from 5.4 still PASSes.
- **Measure audit at session close.** Cross-referenced every measure on `_Measures` against actual usage across all 5 page builds. 15 in active use; 2 redundant (superseded by different build patterns: `SNAP Day Revenue` replaced by `is_snap_day` calc column + Total Revenue donut; `Weekend Revenue %` replaced by IS_WEEKEND axis + Total Revenue bar) — both deleted from model; DAX retained in playbook §2.2/§2.3 for reference. 5 time-intelligence measures (Revenue PY, Revenue YoY $, Revenue YoY %, Revenue YTD, Revenue 30-Day MA) kept as earmarked for 5.7 Executive Overview polish (YoY indicators, YTD pills). Final measure count on `_Measures`: 20 measures + 1 calculated column on `DIM_CALENDAR` (`is_snap_day`).

**Files updated this session (Phase 5 session 5.6):**

- `LEARNINGS.md` — 3 new entries appended to the Power BI section: (a) PBI calculated COLUMN vs MEASURE distinction with clipboard-vs-turnstile mental model; (b) Snowflake unquoted UPPERCASE identifiers carrying through to PBI column names with DAX-authoring discipline rule; (c) `(Mart)` measure naming pattern for forecast-aware models, with carry-forward to Project #3 Data Vault scenarios.
- `PROJECT_CONTEXT.md` — this file. Header date bumped; 5.6 opening directive replaced with 5.7 polish-pass directive carrying forward all discipline rules from 5.4-5.6; 5.6 closeout block inserted above the 5.5 closeout.
- `PROJECT_PLAN.md` — Status block bumped (5.5 closed; 5.6 closed; 5.7 next — polish + drill-through + theme + DAG smoke test).
- `powerbi/retail_demand_forecasting.pbix` — saved. All 5 pages have full visual builds. Total: ~22 visuals across the 5 pages (4 KPI cards + dual-axis trend on Exec Overview; 3 slicers + 2 bars + matrix + Top 10 table on Demand by Hierarchy; 3 slicers + column + donut + scatter on Promotion & Price; 3 slicers + weekday bar + heatmap + holiday bar on Seasonality & Calendar; 2 slicers + 2 line charts + matrix on Forecast vs Actual). 22 measures + 1 calculated column on `_Measures` / DIM_CALENDAR.

**Pending / deferred to session 5.7:**

- Cross-page slicer sync (View → Sync slicers panel for Date + Category).
- Drill-through actions (Demand by Hierarchy → Item Detail; Promotion & Price → Item Detail).
- Format fixes: Revenue Share % → percentage; orphan "Measure" on DIM_CALENDAR → delete; Forecast vs Actual page layout (visuals squashed); scatter bubble Size field; dashed/dotted line styling on forecast charts.
- Theme polish (3-color portfolio palette beyond PBI default).
- VertiPaq Analyzer check on dim cardinalities (interview talk-track artifact).
- End-to-end DAG smoke test (single date) before final Phase 6 close.
- README update with screenshots of all 5 PBI pages (Phase 6).
- POWERBI_PIPELINE.md fill-in for sessions 5.2-5.6 (Phase 6).

---

## Session 5.5 closeout (2026-05-20)

**Headline outcomes:**

- **Pause Visuals identified as silent root cause of the entire session's pain.** At session open, the cat_id slicer on the freshly-cleared Demand by Hierarchy page rendered empty even though `DIM_ITEM` had 3,049 rows with `cat_id` populated (FOODS / HOBBIES / HOUSEHOLD). Repeatedly: clicking anything in PBI made visuals go blank; clicking Home → Refresh forced them to render; the next interaction blanked them again. Spent ~3 hours chasing red herrings (Manage Aggregations check, cyclic reference Power Query trace, DAX calculated column scan, query dependency graph, model relationship audit, save+close+reopen, multiple card recreate cycles). Finally clicked a card to format it and the right pane showed *"To format your visual, refresh it or resume visual queries"* — the word "resume" cracked it open. Optimize ribbon → Pause Visuals was toggled ON. One click off, everything resumed working. The empty slicers, blank cards, and "needs refresh" pattern were all downstream symptoms of paused queries. Locked as the #1 PBI diagnostic check going forward.
- **Spurious cyclic reference on FACT_DAILY_SALES cleared by save+close+reopen.** Mid-session during a refresh, PBI surfaced *"5 queries are blocked: FACT_DAILY_SALES — A cyclic reference was encountered during evaluation."* Traced exhaustively: M-code clean (Source → 3 Navigation steps → drop SALE_KEY), Query Dependencies graph showed 6 queries pulling independently from one Snowflake source with no cross-references, no calculated columns on FACT_DAILY_SALES, all 20 measures present on `_Measures`. After ~30 min of tracing, web search surfaced the crossjoin.co.uk article noting these errors are sometimes spurious. Save → red-X close PBI Desktop → reopen the .pbix from File Explorer cleared the error. Demand by Hierarchy slicers immediately started returning values (the underlying Pause Visuals issue was still in play, but the cyclic-ref red herring was gone).
- **Executive Overview page restored to working state.** During the cross-session re-anchoring before 5.5 opened, the 4 KPI cards on Executive Overview had lost their measure bindings (rendering as empty rectangles with funnel + ... icons). After Pause Visuals was disabled, rebuilt the 4 cards: dragged `Total Revenue` ($100.70M), `Total Units Sold` (36.98M), `Active Stores` (10), `Active Items` (3K) into fresh Card visuals. Also converted the dual-line chart from single-Y-axis to true dual-axis (revenue scale on left 0-150K, units scale on right 0-50K) by moving `Total Units Sold` from the Y-axis field well into the Secondary y-axis field well. Lines overlap visually because units drive revenue (expected), but each measure now has its own scale.
- **Demand by Hierarchy page seeded with title + 3 slicers per playbook §3.2.** Title text box, Date slicer on `DIM_CALENDAR[calendar_date]` (Between mode, 2011-01-29 → 2014-05-22), State slicer on `DIM_STORE[state_id]` (CA / TX / WI), Category slicer on `DIM_ITEM[cat_id]` (FOODS / HOBBIES / HOUSEHOLD). Diagnostic CAT_ID table that was added during the empty-slicer debugging deleted. Bar charts + matrix deferred to 5.6.
- **Pages 3-5 added as title-only stubs.** Promotion & Price, Seasonality & Calendar, Forecast vs Actual page tabs created with titles only. Visual builds deferred to 5.6.
- **Three durable LEARNINGS captured.** (a) Power BI Optimize → Pause Visuals as silent root cause of "everything disappears on click" — locked discipline rule: check this FIRST, before any other PBI diagnostic. (b) Power BI cyclic reference errors can be spurious — close+reopen the .pbix before tracing the model. (c) Power BI new Card visual (Nov 2025 GA) renders blank when bound to a measure that works in other visuals — workaround is Reset to default in Format pane, or delete + recreate, or switch to Multi-row card (in 5.5's case, the apparent Card GA bug was actually a downstream symptom of Pause Visuals, but the carry-forward is real).

**Files updated this session (Phase 5 session 5.5):**

- `LEARNINGS.md` — 3 new entries appended to the Power BI section: Optimize → Pause Visuals as root cause, spurious cyclic reference + reopen workaround, new Card visual GA blank-render bug.
- `TEACHING_PREFERENCES.md` — header date bumped; added 3 new discipline rules: (a) Pause Visuals check FIRST when symptoms suggest paused queries, (b) cyclic ref → save+close+reopen before tracing the model, (c) when 3 things look broken at once, suspect one root cause and try the cheapest single-variable fix first.
- `PROJECT_CONTEXT.md` — this file. Header date bumped; 5.5 opening directive replaced with 5.6 opening directive carrying forward all 5.4 discipline rules plus the new Pause Visuals + cyclic-ref-reopen rules; 5.5 closeout block inserted above the 5.4 closeout.
- `PROJECT_PLAN.md` — status block bumped (5.4 closed; 5.5 closed; 5.6 next).
- `powerbi/retail_demand_forecasting.pbix` — saved. Executive Overview: 4 KPI cards + dual-axis trend chart now working. Demand by Hierarchy: title + 3 slicers. Pages 3-5: title-only stubs.

**Pending / deferred to session 5.6:**

- Demand by Hierarchy — finish: 2 bar charts (revenue by cat_id, revenue by dept_id) + hierarchy matrix (cat → dept → item with Total Revenue + Total Units Sold + Revenue Share %).
- Promotion & Price — full build: 3 slicers + Avg Selling Price by Category column + Revenue by SNAP Day donut + Revenue vs Avg Price scatter. Requires new calculated column `is_snap_day` on `DIM_CALENDAR`.
- Seasonality & Calendar — full build: 3 slicers + Weekend vs Weekday bar + Year × Month heatmap + Holiday event impact bar.
- Forecast vs Actual — full build: Date slicer extended through forecast horizon + Category slicer + Actual + Forecast revenue line on `observation_date` + 95% CI ribbon + cat × series_type matrix.
- Cross-page slicer sync (Date + State + Category), drill-through actions, theme polish — Phase 5.7 or rolled into 5.6 if energy allows.
- Optional Exec Overview polish: line chart visual separation (e.g. Line and Clustered Column for clearer units / revenue distinction).

---

## Session 5.4 closeout (2026-05-20)

**Headline outcomes:**

- **Cortex ML training landed** after warehouse upsize. First attempt at XS warehouse with `method='best' + evaluate=TRUE` hit `STATEMENT_ERROR: Function available memory exhausted` at 1h40m — the ensemble + cross-validation memory footprint exceeded XS RAM. Retry at XL warehouse (16× XS memory) completed in ~15 min. Final landed output: 85,372 forecast rows × 3,049 series × 28 days, horizon 2014-03-24 → 2014-04-20, avg predicted units 11.87. Cost ~1-2 credits total at XL. Carry-forward LEARNINGS entry captures the memory-vs-runtime tradeoff.
- **Forecast layer verified 7× PASS** via new `sql/verify/10_phase5_forecast_layer_verification.sql` — 5 sections (training input sanity, raw output integrity, fact conformance, mart UNION integrity, single-row PASS/FAIL rollup). Matches the `04_`–`09_` house style. One real finding caught: 4 series (~0.13%) collapsed to degenerate CI where `LOWER = FORECAST = UPPER`; not bugs (zero-variance near-zero-demand series), separately counted as `degenerate_ci_series`. Bracket check uses strict `>` so degenerate rows don't false-flag.
- **`dim_calendar` extended 60 days** to cover the forecast horizon + buffer. Model edit: new `future_dates` CTE generates dates via `GENERATOR(60)` + `DATEADD(seq4()+1, MAX(calendar_date))`, UNION ALL with the M5-sourced rows. YML tests on `d`, `wm_yr_wk`, `snap_*` scoped to historical dates via `where: "calendar_date <= DATE '2014-03-23'"` — relaxed not_null tests block future-horizon NULLs from failing. Important caveat: dbt YML test config does NOT support `{{ ref() }}` in where clauses (compilation error), so the cutoff date is hardcoded; if M5 data is ever extended in future projects, the cutoff would need updating.
- **Power BI Phase C complete.** Deleted the 5 old session-5.1 tables (one of which was `MART_EXECUTIVE_OVERVIEW`), reconnected to Snowflake (POWERBI_READER + Import), loaded 8 tables (`AGG_*` ×2, dims ×3, facts ×2, `MART_FORECAST_VS_ACTUAL`), dropped `sale_key` from FACT_DAILY_SALES in Power Query before Apply (final import ~5 min). Built 9 relationships (M:1, single direction) — 3 from FACT to dims, 2 from FACT_FORECAST_DAILY to dim_item+dim_calendar, 2 from MART_FORECAST_VS_ACTUAL to dim_item+dim_calendar, 2 from AGG_* to dim_calendar (later moot once aggs removed). Marked DIM_CALENDAR as Date Table on `calendar_date`. Created dedicated `_Measures` table via `ROW("Placeholder", BLANK())`, hid Placeholder column. Recreated all 20 measures from playbook §2 — 4 base, 3 page-specific, 2 seasonality, 6 forecast-vs-actual, 5 time intelligence. Rebuilt the Executive Overview cards + dual-line trend chart from scratch (the session-5.1 cards lost their bindings when the source tables were deleted, and the new Card visual auto-renders correctly only when measures are properly committed).
- **Manage Aggregations architecturally ruled out for this build.** Tried to wire `AGG_SALES_DAILY` via Modeling → Manage Aggregations, dropdown options for Detail Table appeared unclickable. Web-verified against Microsoft Learn: UDA requires the Detail Table to be in DirectQuery storage mode. Our entire model is Import per the locked playbook §1.1, so UDA is architecturally incompatible. Deleted both AGG tables from the PBI semantic model (still exist in Snowflake + dbt; portfolio narrative preserved as "I built two pre-aggregated marts following the Kimball aggregate pattern"). Net result: measures hit FACT_DAILY_SALES directly via VertiPaq Import — sub-second on 32.9M rows for Sum-based measures anyway, so no measurable performance loss.
- **Three durable LEARNINGS captured** today: (a) Cortex memory sizing — `method='best' + evaluate=TRUE` is MEMORY-heavy not just runtime-heavy, so warehouse size should be picked for headroom not just time budget; XL completed in ~15 min where XS OOM'd at 1h40m. (b) Manage Aggregations × all-Import incompatibility — documented MSFT requirement, can't be worked around without going DirectQuery. (c) PBI measure commit-checkmark quirk — pressing Enter when EDITING an existing measure does NOT commit; you MUST click the green checkmark icon explicitly. Cost ~30 min of mystery debugging in 5.4.

**Files added this session (Phase 5 session 5.4):**

- `sql/verify/10_phase5_forecast_layer_verification.sql` (~165 lines) — durable 5-section verification for the forecast layer matching the `04_`–`09_` house style. Sections 1 + 2 (training input + raw output) runnable immediately after Cortex training; sections 3 + 4 (fact + mart) runnable after `dbt build --select fact_forecast_daily mart_forecast_vs_actual`; section 5 single-row PASS/FAIL rollup. All 7 columns read PASS as at close of 5.4.

**Files updated this session (Phase 5 session 5.4):**

- `dbt/models/warehouse/dim_calendar.sql` — added `future_dates` CTE generating 60 days of future dates; UNION ALL with M5-sourced rows before enrichment. Date-derived attrs computed for future dates; M5-specific attrs NULL.
- `dbt/models/warehouse/_warehouse__models.yml` — relaxed `not_null` tests on `d`, `wm_yr_wk`, `snap_ca`, `snap_tx`, `snap_wi` via `where: "calendar_date <= DATE '2014-03-23'"`. `is_weekend` and `is_holiday` tests left unscoped (those attributes ARE computed for future dates).
- `TEACHING_PREFERENCES.md` — added 2 new bullets: (a) "anything paste-able goes in a code block, always; code blocks first in response, narration after"; (b) "for everything that is NOT paste-able, use plain white text — no inline code formatting; Phil finds the orange/pink inline-code styling against the dark chat background hard to read." Mental test for Claude: would Phil hit Ctrl+C on this? Yes → code block. No → plain text.
- `POWERBI_PLAYBOOK.md` — patched §1.1 (drop `sale_key` ONLY, keep `date_key`; reasoning: VertiPaq dictionary-encodes the ~1,180 distinct dates efficiently) and §1.4 (Manage Aggregations architecturally incompatible with all-Import; agg tables retained in dbt+Snowflake as portfolio narrative only). Also added §3.1 note that the `Active Items` measure was updated to source from fact's `sale_date` not dim_calendar's `calendar_date`, to avoid the future-horizon empty-date trap introduced by the dim_calendar extension.
- `LEARNINGS.md` — 3 new entries (Cortex memory sizing carry-forward; Manage Aggregations × all-Import incompatibility; PBI measure commit-checkmark quirk).
- `PROJECT_CONTEXT.md` — this file. Header date bumped; 5.4 opening directive replaced with 5.5 opening directive carrying forward the locked discipline rules; 5.4 closeout block inserted above the 5.3 block.
- `powerbi/retail_demand_forecasting.pbix` — saved. 8 tables loaded (5 visible: 3 dims + MART_FORECAST_VS_ACTUAL + _Measures; 2 hidden facts; 0 agg tables). 20 measures on `_Measures`. Executive Overview page rebuilt: title, date slicer (2011-01-29 → 2014-05-22), 4 KPI cards, dual-line trend chart.

**Pending / deferred to session 5.5:**

- Pages 2-5 build (Demand by Hierarchy, Promotion & Price, Seasonality & Calendar, Forecast vs Actual) per playbook §3.2-§3.5.
- New calculated column `is_snap_day` on DIM_CALENDAR (Promotion & Price page).
- Cross-page slicer sync, drill-through actions, theme polish — Phase 5.6.

---

## Session 5.3 closeout (2026-05-19)

**Headline outcomes:**

- **Architecture pivoted** from the 2026-05-18 plan (DirectQuery fact + Dual dims + hidden lean mart) to all-Import + user-defined aggregations + Cortex forecast layer. Triggered by: (1) Import → Dual is a documented one-way restriction in PBI Desktop (verified against Snowflake/Microsoft docs), making the original `§6 reset checklist` step 2 mechanically impossible without re-importing as DirectQuery first; (2) deep-research audit concluded the lean-marts pattern was under-engineered, and the professional pattern is topic-scoped aggregations registered as user-defined aggregations.
- **dbt layer rebuilt** end-to-end for the new architecture. 5 new/renamed models built green: `agg_sales_daily` (PASS=4), `agg_sales_daily_item_cat` (PASS=14), `int_forecast_input` (PASS=4 after rebuild at item-level grain). `fact_forecast_daily` + `mart_forecast_vs_actual` ready to build once Cortex overnight training lands.
- **Cortex ML training script** ready. Two failed in-session attempts captured as learnings: item × store at 30K series (cancelled at 2h20min — over-scoped for XS warehouse); item-level with `method='fast'` (cancelled at 10 min when timing missed estimate). Script now configured for portfolio-grade `method='best' + evaluate=TRUE` — Snowflake docs recommend 'best' for <10K series. Expected 60-120 min on XS, run unattended overnight.
- **POWERBI_PLAYBOOK.md fully rewritten** for the new architecture: locked decisions on storage modes (all Import), measure layer (`_Measures`), measure family (FACT-sourced with UDA routing), aggregate tables (two registered as UDAs), forecast layer (Cortex ML item-level grain). Full DAX inventory updated. §6 rebuild checklist replaces the old reset checklist.
- **LEARNING_ROADMAP.md locked** two big items: Project #3 stack (`financial-markets-pipeline-project` — Databricks lakehouse + Data Vault 2.0 in Silver + Gold information marts, MS SQL Server operational source, with 5 open Phase 0 decisions); Post-Project #3 training journey design (6-8 weeks, Claude Code tooling not Cowork, 80/20 code-to-concept split, quiz warm-up format progressing multi-choice → fill-in-blank → type-the-command, hands-on with Phil's own project code).
- **One headline LEARNINGS entry** captured today: ML training workload sizing — sample first, validate at small scale, scale up only when correctness is proven at small scale. Augmented with resolution after both failed Cortex attempts. Carry-forward to Project #3 Databricks workloads.

**Files added this session (Phase 5 session 5.3):**

- `dbt/models/marts/agg_sales_daily.sql` — renamed + restructured from `mart_executive_overview`; now has `date_key` FK to `dim_calendar`. ~1.1K rows.
- `dbt/models/marts/agg_sales_daily_item_cat.sql` — new day × cat_id aggregate (~3.4K rows). Compound PK (date_key, cat_id).
- `dbt/models/intermediate/int_forecast_input.sql` — slim historical view feeding Cortex ML at item-level grain. Aggregates units across stores per (item, day).
- `dbt/models/intermediate/_intermediate__sources.yml` — registers `FORECAST_RAW_OUTPUT` as a dbt source for clean lineage.
- `dbt/models/warehouse/fact_forecast_daily.sql` — 28-day forecast fact. Conforms keys to the warehouse star. Floors negatives at 0. Joins to recent prices for forecast revenue.
- `dbt/models/marts/mart_forecast_vs_actual.sql` — UNIONs actuals from `fact_daily_sales` with forecast from `fact_forecast_daily`. Discriminator column `series_type`. Powers the PBI Forecast vs Actual page.
- `sql/snowflake/05_train_forecast_model.sql` — Snowsight script. Trains Cortex ML model and lands forecast output into `RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT`. Configured for portfolio-grade `method='best' + evaluate=TRUE`.

**Files updated this session:**

- `dbt/models/marts/_marts__models.yml` — added schema/tests for both new mart files.
- `dbt/models/intermediate/_intermediate__models.yml` — added `int_forecast_input` entry, updated description after item-level grain switch.
- `dbt/models/warehouse/_warehouse__models.yml` — added `fact_forecast_daily` entry with full test suite (compound unique on (item_id, forecast_date), FK relationships, accepted_range on measures).
- `POWERBI_PLAYBOOK.md` — rewritten end-to-end. 8 sections with new §6 rebuild checklist.
- `LEARNINGS.md` — added the ML training workload sizing entry under Snowflake; augmented with resolution paragraph.
- `LEARNING_ROADMAP.md` — Project #3 locked-stack section + Training Journey full-design section + Notes/changes entries (3 new).
- `PROJECT_CONTEXT.md` — this file. Header date bumped, 5.3 closeout block added, session 5.4 opening directive added.

**Files deleted this session:**

- `dbt/models/marts/mart_executive_overview.sql` — replaced by `agg_sales_daily.sql` (rename + structural change).
- `dbt/models/intermediate/int_forecast_input_item.sql` — temporary fallback file; absorbed into `int_forecast_input.sql` once item-level grain was locked.
- `sql/snowflake/05a_train_forecast_model_item_level.sql` — temporary fallback script; absorbed into `05_train_forecast_model.sql`.

**Pending / deferred to session 5.4:**

- Cortex overnight training completion + smoke-test verification
- `dbt build --select fact_forecast_daily mart_forecast_vs_actual` (depends on Cortex output existing)
- Phase B: Snowflake verification SQL (`sql/verify/10_phase5_forecast_layer_verification.sql`)
- Phase C: Power BI semantic model rebuild
- Phase D: Page builds (all 5)
- Phase E: Polish + commit

---

## Where we are right now

**Current phase:** **Phase 5 session 5.2 ✅ DONE.** RAW data gap fully closed end-to-end: 68 missing dates between `ds=2014-01-06` and `ds=2014-03-14` backfilled via Airflow extract-only mode (`--task-regex extract_one_day -i --reset-dagruns`) over ~2h sequential + 1 manual extract for an Airflow context anomaly; `dbt build --full-refresh` rebuilt the full DAG in 34s with **PASS=78**; `FACT_DAILY_SALES` now spans 2011-01-29 → 2014-03-22 continuously (gap query returns zero rows). Executive Overview KPIs grew from session-5.1's $93.80M / 34.52M units to **$100.70M / 36.98M units** (+$6.9M revenue / +2.46M units from 68 newly-loaded dates). Active Stores still 10, Active Items still ~2.46K peak. **MID-SESSION ARCHITECTURE RESET TRIGGERED** when building the Demand by Hierarchy page surfaced a measure-layer bug: the 4 session-5.1 measures (Total Revenue, Total Units Sold, Active Stores, Active Items) were all created on `MART_EXECUTIVE_OVERVIEW` columns. The mart has no relationship to `DIM_ITEM` or `DIM_STORE` (only `DIM_CALENDAR`), so slicing by `cat_id` showed all three categories (FOODS, HOUSEHOLD, HOBBIES) with the identical $93.8M grand total. Design-cascade bug, not a typo — the lean-marts pattern drops item/store identifiers at mart-build time, so cross-dim slicing requires fact-based measures. Spawned parallel deep research (project state audit + web research over Microsoft Learn / SQLBI / Chris Webb / RADACAD) and synthesized findings into **`POWERBI_PLAYBOOK.md`** at repo root. Playbook locks 4 architectural decisions: (a) **Dual storage mode** on `DIM_ITEM` / `DIM_STORE` / `DIM_CALENDAR` to avoid limited-relationship traps with the DQ fact; (b) dedicated hidden **`_Measures` table** for all measures (SQLBI / Microsoft Learn pattern); (c) **single fact-based measure family** — never the mart, which becomes hidden in PBI; (d) **no Manage Aggregations** in v1 — deferred to 5.6 polish as interview talk-track. Full DAX formulas for sessions 5.2-5.6, page-by-page visual specs, free-Desktop tier confirmation, 16+ web sources cited at bottom of playbook. **Reset execution itself deferred to session 5.3** (8-step checklist in playbook §6) to avoid cramming destructive PBI changes at end of a long session. Also banked: **Airflow extract context anomaly** (extract task marked SUCCESS for ds=2014-01-06 but no rows landed; direct script run from PowerShell loaded all 30,490 rows in 2 minutes — root cause suspected in Cosmos-DAG context/ds resolution under `--reset-dagruns` + `--task-regex` mode, not definitively proven, documented as known anomaly + ground-truth-via-direct-execution diagnostic pattern); and the **Airflow backfill anti-pattern lesson** (initial Claude proposal was full chain × 68 dates ~5-6h; corrected to extract-only ~25 min sequential — 12× speedup, discipline rule added to TEACHING_PREFERENCES). **Phase 5 session 5.3 next**: PBI architecture reset (playbook §6) → Demand by Hierarchy page → Promotion & Price page.

**Last action (2026-05-18 — Phase 5 session 5.2):** Three major outcomes in one long session: (1) RAW data gap closure end-to-end; (2) PBI architecture reset triggered by mid-session bug, producing a research-backed locked playbook; (3) Airflow extract anomaly diagnosed via ground-truth-via-direct-execution. Session opened with a planned 25-min Airflow backfill but Claude mis-led the kickoff sequence — initial proposal was the full chain × 68 dates (~5-6h sequential, ~1-2h parallel) instead of the correct `--task-regex extract_one_day -i` extract-only pattern (~25 min). Phil caught this and corrected approach used. Backfill ran during Phil's break: 67 of 67 dates succeeded over ~2h (~107s per extract — slower than the 20-30s/run optimistic estimate due to Azure SQL ↔ Snowflake transfer time for 30,490 rows + 26,049 sell_prices rows per date). Post-backfill parity check showed 1,149 of 1,150 expected distinct dates loaded — one date (2014-01-06 = d_1074) silently skipped despite Airflow marking the task SUCCESS. Diagnosed via direct-execution: ran `python scripts/extract_azure_to_snowflake.py --run-date 2014-01-06` from PowerShell; loaded all 30,490 sales_train rows + 26,049 sell_prices rows + 1 calendar row in 2 minutes (~123s). Conclusion: Azure SQL has the data (verified directly — `raw.calendar` has 1,969 rows including d_1074) and the extract script works correctly; the bug lives somewhere in the Airflow context/ds resolution during `--reset-dagruns` + `--task-regex` backfill mode. Wrote temporary `scripts/check_azure_sql_calendar_gap.py` diagnostic that re-used the production extract module's connection helpers to confirm Azure SQL state; script deleted at session close, diagnostic pattern captured in LEARNINGS. After data fix: `dbt build --full-refresh` ran cleanly from `dbt/` directory (PASS=78 in 34.00s — slower than session 6's 17.72s figure, likely due to 67 new dates flowing through incremental MERGE on the fact). FACT_DAILY_SALES gap query returned zero rows confirming end-to-end continuity. PBI refresh on `powerbi/retail_demand_forecasting.pbix` showed continuous Jan-Mar 2014 line chart, KPIs grown to $100.70M / 36.98M units. **Mid-session, separate from the backfill work**: while planning the Demand by Hierarchy page, dragging `MART_EXECUTIVE_OVERVIEW.TOTAL_REVENUE_USD` sliced by `DIM_ITEM.cat_id` showed all three categories with identical $93.8M. Root-caused as design-cascade bug — mart has only one relationship in PBI (to `DIM_CALENDAR`); lean-marts design dropped item_id and store_id at mart-build time; filter from cat_id has no path to mart → no filtering → grand total for every slice. Triggered architecture-reset via parallel deep research (one agent auditing project state from docs + dbt files, one agent web-researching free PBI Desktop tier + composite model best practice + cross-table measure consistency + DirectQuery DAX limitations + 2026 UI specifics). Synthesized findings into `POWERBI_PLAYBOOK.md` at repo root — 4 architectural decisions locked, full DAX formulas across §2.2-§2.5, page-by-page visual specs in §3, free-tier confirmation in §4, discipline rules in §5, session-5.3 reset checklist in §6. **Reset execution itself deferred to session 5.3** (Phil's call after a long session; destructive PBI changes deserve a fresh start). One existing `scripts/check_azure_sql_calendar_gap.py` file deleted at close (purpose served).

**Files added this session (Phase 5 session 5.2):**

- `POWERBI_PLAYBOOK.md` (~450 lines) — the locked, research-backed plan for Phase 5 sessions 5.2 → 5.6. Six sections: locked architectural decisions, measure inventory + DAX formulas, page-by-page visual plan, free-Desktop tier confirmation, discipline rules, session-5.3 reset checklist. 16+ web sources cited at bottom (Microsoft Learn, SQLBI, Chris Webb, RADACAD). Replaces ad-hoc session-by-session PBI planning with a single source of truth.

**Files updated this session (Phase 5 session 5.2):**

- `PROJECT_CONTEXT.md` — this file. Header date bumped; "Current phase" rewritten for session-5.2 closure; session-5.2 closeout block inserted above the session-5.1 block; two mid-session forward-looking handoff blocks replaced with a single session-5.3 opening directive pointing at `POWERBI_PLAYBOOK.md`.
- `LEARNINGS.md` — appended 7 new entries: mart-sourced measures break when sliced by non-calendar dims (design-cascade bug + carry-forward principle for Project #3); dedicated hidden `_Measures` table convention (SQLBI / Microsoft Learn pattern); Dual storage mode on dims joined to DirectQuery fact (regular vs limited relationships); Airflow backfill anti-pattern (full chain × N vs `--task-regex` single-task × N — 12× speedup); research-backed playbook as a mid-phase reset tool (meta-lesson for cascading-design-choice failures); explicit DAX measures over implicit aggregations (already had; reinforced).
- `TEACHING_PREFERENCES.md` — added 2 substantive bullets: PBI architectural discipline rules (verify state before prescribing, `_Measures` table convention, fact-not-mart, Dual storage, named measures not raw columns, explain rollback paths first); "don't propose 5-hour runs when 25-min alternatives exist" anti-pattern rule.
- `PROJECT_PLAN.md` — Status block bumped (5.1 closed; 5.2 closed; 5.3 next).

**Files deleted this session (Phase 5 session 5.2):**

- `scripts/check_azure_sql_calendar_gap.py` — one-off diagnostic script written mid-session to confirm Azure SQL has d_1074 / 2014-01-06 (it does — 1,969 rows total in raw.calendar). Purpose served; the diagnostic technique (re-use production extract module's connection helpers via Python import; query directly to ground-truth ambiguous states) captured durably in LEARNINGS. Clean repo wins.

**Headline outcomes from this session (Phase 5 session 5.2):**

- **RAW data gap closed end-to-end with full-DAG dbt rebuild.** 68 missing dates landed in RAW.SALES_TRAIN + RAW.CALENDAR; `dbt build --full-refresh` rebuilt STAGING → INTERMEDIATE → WAREHOUSE → MARTS with PASS=78 in 34s; FACT_DAILY_SALES gap query confirms zero gaps; Executive Overview KPIs grew $93.80M → $100.70M revenue.
- **`POWERBI_PLAYBOOK.md` shipped as the locked source of truth for sessions 5.2 → 5.6.** Architectural decisions web-verified against Microsoft Learn / SQLBI / Chris Webb / RADACAD. Locks the failure mode that triggered the mid-session reset (mart-based measures sliced by non-calendar dims) and prevents recurrence on pages 5.3-5.5.
- **Three real engineering insights captured as durable LEARNINGS**: (a) mart-sourced measures break when sliced by item/store dims (design-cascade bug with carry-forward principle for any pre-agg model); (b) Airflow extract context anomaly + ground-truth-via-direct-execution diagnostic pattern; (c) Airflow backfill anti-pattern (full chain × N vs `--task-regex extract_one_day -i` × N = 12× speedup for unattended backfills).
- **Self-correction discipline demonstrated.** Phil pushed back on Claude's initial 5-hour backfill proposal AND on cascading PBI step-by-step iteration after the measure bug. Both pushbacks led to better outcomes (25-min backfill, research-backed playbook) and durable discipline rules. The "don't propose 5-hour runs when 25-min alternatives exist" anti-pattern rule now banked in TEACHING_PREFERENCES.
- **Backfill executed during break** — proves the "set-and-walk-away" pattern is genuinely operational; Phil's perfectionist follow-up on the 1-missing-date anomaly proved the verification checklist earns its keep.

**Next session (Phase 5 session 5.3) — PBI architecture reset + Demand by Hierarchy + Promotion & Price:**

1. **Read `POWERBI_PLAYBOOK.md` end-to-end** before touching the .pbix. Especially §1 (locked decisions), §2 (measure inventory + DAX formulas), §6 (reset checklist).
2. **Execute the 8-step PBI reset** (playbook §6): switch 3 dims to Dual mode → create `_Measures` table → hide placeholder column → rebuild 4 base measures on `_Measures` from FACT → re-wire Executive Overview visuals to new measures → delete old mart-based measures → hide `MART_EXECUTIVE_OVERVIEW` table from report view → verify Executive Overview still renders ~$100.70M / 36.98M / 10 / 3,049-or-2.46K (decide Active Items semantic per playbook §3.5.2.A note).
3. **Build Demand by Hierarchy page** (playbook §3.5.2.B): 3 slicers (date/state/category), 2 bar charts (revenue by `cat_id`, revenue by `dept_id`), 1 hierarchy matrix (cat → dept → item with Total Revenue + Total Units Sold + Revenue Share %).
4. **Build Promotion & Price page** (playbook §3.5.2.C): same 3 slicers, Avg Selling Price by category column chart, Revenue by SNAP Day donut (with a new calculated column `is_snap_day` on DIM_CALENDAR), Revenue vs Avg Price scatter (one bubble per dept).
5. **POWERBI_PIPELINE.md fill-in** — sections for the reset + both new pages (matching session 5.1's depth).
6. **10-point + phase-boundary audits + bundled commit.**

**Last action (2026-05-18 — Phase 5 session 1):** Opened the Power BI layer end-to-end. Shipped `sql/snowflake/04_grant_powerbi_reader.sql` — new POWERBI_READER role with USAGE on `WH_RETAIL` + `RETAIL_DB`, USAGE + SELECT (existing + future tables/views) on `WAREHOUSE` and `MARTS` schemas, NO grants on RAW/STAGING/INTERMEDIATE; granted to user PHELUCIAM as a second role alongside RETAIL_ENGINEER (reuse-existing-user pattern over service-account, chosen as the most-professional default for a single-developer learning context). Verified end-to-end in Snowsight: 5 numbered query blocks (provision + role-switch + mart smoke-test + fact smoke-test + grants audit + negative-test on RAW) all returned expected results; SHOW GRANTS shows only 9 USAGE/SELECT rows. Scaffolded `powerbi/` folder at repo root (peer to `dbt/`, `airflow/`); created `POWERBI_PIPELINE.md` walkthrough at repo root matching `EXTRACT_PIPELINE.md` + `DBT_PIPELINE.md` pattern. PBI Desktop connection wired via native Snowflake connector with Server `tq94402.ap-southeast-2.snowflakecomputing.com` + Warehouse `WH_RETAIL` + Advanced Options → Role name `POWERBI_READER`. **One mid-session diagnostic** done well: PBI's Navigator initially showed 7 schemas under POWERBI_READER (including RAW/STAGING/INTERMEDIATE — surprising). Instead of guessing, ran `INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER('PHELUCIAM')` which proved every PBI metadata query (`SHOW SCHEMAS`, `SHOW DATABASES`, `SELECT CURRENT_VERSION()`) ran under POWERBI_READER. Boundary confirmed bit on RAW with a `SELECT COUNT(*) FROM RETAIL_DB.RAW.M5_SALES_TRAIN` returning "Object does not exist or not authorized" — the schema listing was Snowflake's metadata behavior, not a privilege leak. Ground-truth-via-query-history beats guessing-from-symptoms. Loaded `MART_EXECUTIVE_OVERVIEW` (1,081 rows) for the smoke test, then `FACT_DAILY_SALES` (32,959,690 rows) + `DIM_CALENDAR` (1,082) + `DIM_ITEM` (3,049) + `DIM_STORE` (10) for the semantic model. Disabled autodetect-relationships (CURRENT FILE) and auto-date-time (CURRENT FILE + GLOBAL) before adding the warehouse tables — Project #1 carry-forwards locked in. Manually built 4 relationships: 3× fact→dim many-to-one single-direction through surrogate keys; 1× mart→`dim_calendar` *overridden* from PBI's auto-detected 1:1 to many-to-one (Single cross-filter) to preserve star-schema purity. **Executive Overview page** built: text-box title; date-range slicer on `dim_calendar.calendar_date` (Between mode, slider with two handles); 4 KPI Cards using explicit DAX measures (`Total Revenue` $93.80M, `Total Units Sold` 34.52M, `Active Stores` 10, `Active Items` 2.46K — `MAX()` for the per-day counts, `SUM()` for the totals); dual-axis line chart showing both `Total Revenue` and `Total Units Sold` over `dim_calendar.calendar_date` — visible weekly seasonality + three Christmas dips + steady growth + rightmost session-6 jump. Saved to `powerbi/retail_demand_forecasting.pbix`. Trend-line workaround flagged for 5.6 polish (dual-axis charts hide trend-line option; split into side-by-side single-measure charts would unlock it). **Two real PBI gotchas hit and resolved**: (a) credential cache desync — first connection attempt failed with `ODBC: 260002 Password is empty`; root cause was Power BI saves credentials separately from connection settings, so editing one without the other desyncs. Fix: File → Options → Data source settings → Clear Permissions + Delete → reconnect from scratch with auth re-entered. (b) UI element version variance — initial instruction referenced "Card" vs "Card (new)" as two options; web-confirmed the new Card visual replaced the classic as default in Nov 2025 GA, so Phil's Visualizations pane shows only one Card option. Web-check discipline rule added to TEACHING_PREFERENCES. **One data observation flagged**: revenue chart shows a real gap between late-Jan-2014 and 2014-03-22 (session 6's new dates), caused by sporadic Phase 3 testing rather than continuous DAG runs. Backfill queued for end-of-session via `airflow dags backfill` — runs unattended during break.

**Files added this session (Phase 5 session 1):**

- `sql/snowflake/04_grant_powerbi_reader.sql` — provisions POWERBI_READER role with least-privilege grants. ~50 lines. Banner header + section dividers + comments-above-the-line matching `00_/03_` house style. Includes 5 numbered verify blocks (smoke-test mart count, smoke-test fact count, SHOW GRANTS audit) + commented-out negative-test on RAW for re-runnable boundary proof.
- `powerbi/retail_demand_forecasting.pbix` — Power BI Desktop file. Saved with: 5-table semantic model (fact + 3 dims + 1 mart), 4 relationships under lean-marts pattern, autodetect + auto-date-time both off, Executive Overview page built (title + slicer + 4 KPI cards + dual-axis trend chart). All measures explicit DAX.
- `POWERBI_PIPELINE.md` — walkthrough doc at repo root matching EXTRACT_PIPELINE / DBT_PIPELINE pattern. Initial Phase 5 session 1 scaffold with front matter, retail-clerk-on-a-tour analogy, architecture diagram, table of the five pages mapped to sessions, and section placeholders for sessions 5.2–5.6.

**Files updated this session (Phase 5 session 1):**

- `TEACHING_PREFERENCES.md` — added 3 substantive bullets: **BI tool** entry (PBI Desktop is universally free, no paid Desktop tier; the free/paid split is Desktop vs Service; Phil's Desktop UI may differ from Claude's mental model because PBI ships continuous UI updates — web-check or ask before asserting); **UI walkthrough pacing rule** (1-2 steps per chunk, 2-3 absolute max for any new tool, especially PBI Desktop — stop after 1-2 steps and wait for confirmation, the "yell when done" pattern only works for genuinely linear tasks like data loads not multi-dialog UI flows).
- `LEARNINGS.md` — appended 5 new entries spanning the Snowflake, Power BI, and discipline-rule sections covering today's gotchas (see "Headline outcomes" below for the list).
- `PROJECT_PLAN.md` — Status block bumped from "Phase 4 closed; Phase 5 session 1 next" to "Phase 5 session 1 closed; Phase 5 session 2 next (Demand by Hierarchy + Promotion & Price pages)."
- `PROJECT_CONTEXT.md` — this file. Header date bumped; "Current phase" paragraph rewritten; new session 5.1 closeout block inserted above the session 6 block; session 6 block preserved as historical record.

**Files deleted this session (Phase 5 session 1):**

- `powerbi/.gitkeep` — stale scaffolding from earlier in the same session; folder now contains `retail_demand_forecasting.pbix` (real content). Same pattern as the dbt `.gitkeep` deletions in Phase 4 session 5.

**Headline outcomes from this session (Phase 5 session 1):**

- **End-to-end Snowflake → Power BI connection live.** POWERBI_READER role pinned at the connection level; SELECT boundary holds (verified via negative test); the principle-of-least-privilege story is now on disk in a runnable SQL artifact, not just claimed in docs.
- **Semantic model in place with star-schema discipline.** 4 relationships, all single-direction filter flow, autodetect off, no implicit measures anywhere. Mart→calendar 1:1 → many-to-one override pattern documented as durable LEARNINGS entry.
- **Executive Overview page complete for the README screenshot.** Title + slicer + 4 KPI cards + dual-axis trend chart. ~30,500× compression visible (1,081 mart rows powering the home page rather than 32.9M fact rows direct).
- **Five durable LEARNINGS entries captured**: (a) Snowflake metadata visibility ≠ access boundary (visitor-badge analogy); (b) PBI explicit vs implicit measures (recipe-on-the-wall analogy); (c) mart→calendar 1:1 cardinality override pattern; (d) PBI dual-axis charts disable trend lines (version-independent constraint); (e) PBI Desktop UI version variance + web-check discipline rule.
- **Ground-truth-first diagnostic pattern** demonstrated. When PBI's Navigator showed unexpected schemas, used `INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER` to prove what role each metadata query actually ran under — beat guessing-from-symptoms decisively. Carry-forward principle for Project #3.
- **Backfill queued cleanly** for end-of-session via `airflow dags backfill` — proves the LEARNINGS entry from earlier today about Airflow's scheduler-owns-the-cursor pattern is genuinely operational, not theoretical.

**Next session (Phase 5 session 2) — Demand by Hierarchy + Promotion & Price pages:**

1. **Decision: backfill approach + execution.** The late-Jan-2014 → mid-March-2014 gap is still open at session 5.1 close — naive `airflow dags backfill` won't fix it because the fact's `is_incremental()` clause is forward-only (per the LEARNINGS entry from Phase 4 session 6). Three real options: (a) `dbt run --full-refresh --select fact_daily_sales` after extracting the missing dates — rebuilds the fact from STAGING, heavier compute but clean; (b) temporarily modify the incremental WHERE to `NOT IN (SELECT DISTINCT sale_date FROM {{ this }})` for one run — surgical but is a code change; (c) manual MERGE statement against the fact for missing dates — bypasses dbt for the gap. Pick the approach early in 5.2, execute, then verify gap closure via `SELECT MIN(sale_date), MAX(sale_date), COUNT(DISTINCT sale_date) FROM RETAIL_DB.WAREHOUSE.FACT_DAILY_SALES` and refresh the .pbix.
2. **DirectQuery vs Import evaluation for slicing pages.** Both new pages slice the warehouse star directly (not the mart). The fact's 32.9M rows are already loaded in Import mode from 5.1 — measure first-render performance and refresh-time on the new visuals; if either chokes, evaluate composite mode (DirectQuery on fact, Import on dims). Empirical-per-page principle.
3. **Demand by Hierarchy page** — item category / department / store-state slicer chain. Visuals: revenue and units broken down by `dim_item.cat_id` / `dept_id`, with drill-from-overview pattern. Date slicer carried over from page 1.
4. **Promotion & Price page** — sourced from `int_sales_with_prices` enrichment in `WAREHOUSE.fact_daily_sales` (sell_price + revenue_amount_usd columns). Visuals: revenue vs price scatter, promotional period markers, snap-day SNAP flag breakdown.
5. **Page-specific DAX measures.** New measures for each page beyond the global Total Revenue / Total Units Sold (e.g., AVG selling price, units per item per day, distinct item count by category).
6. **POWERBI_PIPELINE.md** session-5.2 fill-in (Demand by Hierarchy + Promotion & Price sections).
7. **10-point + phase-boundary audits + bundled commit.**

---

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
2. ✅ Added `verify_one_day` @task downstream of `extract_one_day` in `m5_daily_extract`. Three Snowflake-side checks batched into one SQL round-trip. Task chain: `extract_one_day() >> verify_one_day()`.

---

## Fast-forward + v1.0.1 patch (appended 2026-05-22)

> Honest note on this file: detailed per-session logging in PROJECT_CONTEXT.md ended at Phase 3 session 2. Phases 3 (rest) through 6 were captured in `LEARNINGS.md` (technical entries + carry-forwards) and `LEARNING_ROADMAP.md` (cross-project context). This appended block records the post-v1.0 patch specifically, because it happened after shipping and warrants its own rolling-state entry.

### v1.0.1 patch — 2026-05-22 (later, same day as v1.0 ship)

**Trigger.** First CI run on the v1.0 ship commit (`2a737a5`) failed with a red X on the main branch — the headline portfolio commit visible to every repo visitor. Root cause: `dbt/.sqlfluff` was configured with the jinja templater + `apply_dbt_builtins = true`, which resolves dbt-core macros (ref/source/var) but NOT package macros. Project #2 uses `dbt_utils.generate_surrogate_key()` in 5 SQL models. sqlfluff couldn't parse the unresolved jinja and cascaded into 30+ bogus errors. Full saga + Project #3 carry-forwards in `LEARNINGS.md` under the dated entry "2026-05-22 (later) — v1.0.1 patch".

**What changed:**

1. `dbt/.sqlfluff` — templater switched from `jinja` to `dbt`. Added `[sqlfluff:templater:dbt]` section.
2. `.github/workflows/dbt-ci.yml` — `sqlfluff-lint` job rewired to use real Snowflake creds via 7 encrypted GitHub Actions Secrets (SNOWFLAKE_ACCOUNT / USER / PASSWORD / ROLE / WAREHOUSE / DATABASE / SCHEMA). Added install steps for `dbt-core==1.11.10`, `dbt-snowflake==1.11.5`, `sqlfluff-templater-dbt>=3.0.0`, and a `dbt deps` step. dbt-parse job kept its dummy creds (dbt parse doesn't connect).
3. 8 dbt models auto-fixed via `sqlfluff fix --force models/` locally (LT01 spacing, LT02 indentation, CP01 keyword case, AL01 implicit aliasing).
4. 2 dbt models manually reindented where auto-fix couldn't safely reindent multi-line CTE bodies: `int_sales_with_prices.sql` (joined CTE), `agg_sales_daily_item_cat.sql` (aggregated CTE).
5. Workflow file + .sqlfluff header comments updated to reflect the new design + the documented degradation plan for when the Snowflake trial expires (~2026-06-12).

**Commits:**

- `421be09` — "ci: switch sqlfluff to dbt templater + secrets" (workflow + config change).
- `d434493` — "ci: fix sqlfluff style violations in dbt models" (auto-fix + manual reindents).
- (docs commit pending — this PROJECT_CONTEXT.md entry, LEARNINGS.md new entry, CODE_QUALITY.md inline correction, README.md CI bullets corrected).

**Resulting CI status:** GREEN on commit `d434493`. Both `dbt-parse` (37s) and `sqlfluff-lint` (42s) jobs passing. Red X on the v1.0 ship commit (`2a737a5`) remains in history — that's normal and unavoidable for past commits.

**Project #3 carry-forwards banked:** see `LEARNINGS.md` v1.0.1 patch entry, "Carry-forward to Project #3 (CRITICAL — bake into Phase 0)" subsection. Seven specific Phase 0 carry-forwards covering templater choice, secrets-in-CI, trial-expiry degradation plan, local-lint-before-first-push discipline, auto-fix limits, cascading-error diagnostic discipline, and recruiter-facing badge value.

**Status:** Project #2 v1.0.1 is the current shipped state. Project #3 (`financial-analytics-lakehouse-project`) folder created with the three carry-forward .md files (TEACHING_PREFERENCES, LEARNING_ROADMAP, LEARNINGS — but LEARNINGS needs re-copying post-v1.0.1 to pick up the patch entry). Per-check logging added.
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
