# POWERBI_PLAYBOOK.md — Sessions 5.2 → 5.6 Locked Plan

> **Purpose.** Single source of truth for the Power BI build through end-of-Phase-5. Drafted 2026-05-18 during Phase 5 session 5.2 reset after a measure-architecture bug surfaced mid-session. Backed by a documented project-state audit + web-verified Microsoft Learn / SQLBI / RADACAD / Chris Webb sources (see Sources at bottom).
>
> **How to use.** Read top-to-bottom at the start of every Phase 5 session. Each session's step list is meant to be followed exactly — deviations need to be justified in chat before executing. The architectural decisions in §1 are LOCKED; do not relitigate them unless evidence forces it.

---

## 1. Locked architectural decisions (research-backed)

### 1.1 Storage modes — Dual on dims, DirectQuery on fact, Hidden Import on mart

| Table | Current (session 5.1) | Locked target (session 5.2 reset) | Reason |
|---|---|---|---|
| `FACT_DAILY_SALES` | DirectQuery | DirectQuery | 32.9M rows; Import-only attempt produced 949 MB .pbix that exceeded GitHub's 100 MB limit |
| `DIM_CALENDAR` | Import | **Dual** | Dual lets PBI answer dim-only queries from cache AND join cleanly with DQ fact at source — avoids "limited relationship" traps that come with pure Import dims + DQ fact |
| `DIM_ITEM` | Import | **Dual** | Same |
| `DIM_STORE` | Import | **Dual** | Same |
| `MART_EXECUTIVE_OVERVIEW` | Import | **Import, hidden** | Kept loaded as documentation of the lean-marts pattern; hidden from field list so it doesn't tempt drag-and-drop into visuals; no measures reference it after the reset |

**Why Dual not Import for dims:** SQLBI / Marco Russo — a relationship between an Import dim and a DirectQuery fact is a *limited* (weak) relationship. Limited relationships: (a) can't use `RELATED` to fetch a column across them, (b) skip table expansion, (c) use INNER JOIN semantics (drops unmatched rows from BOTH sides), (d) get slow on high-cardinality join keys. Setting dims to Dual makes the relationships *regular* at query time. Free in Desktop, zero downside for this stack.

### 1.2 Measure layer — dedicated hidden `_Measures` table

All measures live on a single empty hidden table called `_Measures`. Convention enforced by Microsoft Learn + SQLBI. Reasons:

- Measures don't need a data home — they're computed expressions. Putting them on a data table mixes "things to drag" with "things to compute" and clutters the field list.
- A dedicated table sorts alphabetically before all the data tables (leading underscore convention) and keeps measure organization independent of which table happens to be the source.
- Refactoring a measure to reference a different fact column is trivial when the measure has no data-table home.

**How to create:** Modeling tab → New table → `_Measures = ROW("placeholder", "")` (creates a 1-row dummy table). Hide the placeholder column. Then every new measure: in the Fields pane, right-click `_Measures` → New measure. PBI auto-homes the measure on `_Measures`.

### 1.3 Single measure family — sourced from `FACT_DAILY_SALES`, NOT from mart

All measures aggregate the FACT, not the MART. This is the **non-negotiable** decision from this reset. Reasons:

- The mart has no relationship to `DIM_ITEM` or `DIM_STORE`. Mart-sourced measures sliced by item/store dims will show the same value for every slice (the grand total). This is what Phil hit in session 5.2 mid-session — predictable consequence of the lean-marts design.
- Fact-sourced measures slice correctly by every dim because the fact has active many-to-one relationships to all three.
- Single measure family across all 5 pages = single source of truth, no "the two dashboards disagree" tickets.
- Performance: 32.9M-row Snowflake fact aggregated by a column-stored Snowflake warehouse is sub-second for the visuals we're building. DirectQuery is not a bottleneck here.

**What about Manage Aggregations?** SQLBI's canonical pattern: Define mart as a managed aggregation; PBI rewrites simple queries to hit the agg transparently. **Deferred to session 5.6 polish or out-of-scope for this project.** Worth mentioning as an interview talk-track ("could have wired the day-grain mart as a managed aggregation for sub-ms exec page perf — chose to keep the model simple") but not building it in 5.2.

### 1.4 Mart fate — hide in PBI, keep in dbt

The mart stays as a dbt asset (model file unchanged, still builds, still tested). In PBI: hidden from field list, but kept loaded so the model view still shows the relationship to `DIM_CALENDAR`. The portfolio narrative becomes:

> "The dbt project includes a `mart_executive_overview` model that pre-aggregates the fact to day grain. In Power BI we evaluated using it as a managed aggregation but chose to keep a single fact-sourced measure family for cross-page consistency. The mart is loaded but hidden, demonstrating the lean-marts pattern in the data layer without coupling the BI semantic model to it."

---

## 2. Measure inventory — current vs target

### 2.1 Currently in `.pbix` (as of session 5.2 mid-reset)

All four currently reference `MART_EXECUTIVE_OVERVIEW` columns. They must be retired during the 5.2 reset.

| Measure | Current home | Current formula | Status |
|---|---|---|---|
| Total Revenue | MART_EXECUTIVE_OVERVIEW | `SUM(MART_EXECUTIVE_OVERVIEW[total_revenue_usd])` | **DEPRECATE** |
| Total Units Sold | MART_EXECUTIVE_OVERVIEW | `SUM(MART_EXECUTIVE_OVERVIEW[total_units_sold])` | **DEPRECATE** |
| Active Stores | MART_EXECUTIVE_OVERVIEW | `MAX(MART_EXECUTIVE_OVERVIEW[active_store_count])` | **DEPRECATE** |
| Active Items | MART_EXECUTIVE_OVERVIEW | `MAX(MART_EXECUTIVE_OVERVIEW[active_item_count])` | **DEPRECATE** |

### 2.2 Session 5.2 base measures (4 — rebuild on `_Measures` from FACT)

```dax
Total Revenue =
SUM ( FACT_DAILY_SALES[revenue_amount_usd] )

Total Units Sold =
SUM ( FACT_DAILY_SALES[units_sold] )

Active Stores =
DISTINCTCOUNT ( FACT_DAILY_SALES[store_key] )

Active Items =
DISTINCTCOUNT ( FACT_DAILY_SALES[item_key] )
```

Format each as currency / whole number with thousands separators. `Total Revenue` as `$#,0` (no decimals at $93.8M scale).

### 2.3 Session 5.2 page-specific measures (Demand by Hierarchy + Promotion & Price — 4 new)

```dax
Revenue Share % =
DIVIDE (
    [Total Revenue],
    CALCULATE ( [Total Revenue], ALL ( DIM_ITEM ) )
)

Avg Selling Price =
AVERAGEX (
    FILTER ( FACT_DAILY_SALES, FACT_DAILY_SALES[sell_price] > 0 ),
    FACT_DAILY_SALES[sell_price]
)

Units per Item per Day =
DIVIDE ( [Total Units Sold], [Active Items] )

SNAP Day Revenue =
CALCULATE (
    [Total Revenue],
    FILTER (
        DIM_CALENDAR,
        DIM_CALENDAR[snap_ca] = 1
            || DIM_CALENDAR[snap_tx] = 1
            || DIM_CALENDAR[snap_wi] = 1
    )
)
```

### 2.4 Session 5.3 page-specific measures (Seasonality & Calendar — 2 new)

```dax
Weekend Revenue % =
DIVIDE (
    CALCULATE ( [Total Revenue], DIM_CALENDAR[is_weekend] = TRUE ),
    [Total Revenue]
)

Holiday Revenue =
CALCULATE ( [Total Revenue], DIM_CALENDAR[is_holiday] = TRUE )
```

### 2.5 Session 5.5 time intelligence measures (5 new — well-optimized DirectQuery picks)

Per Chris Webb's Nov 2025 DirectQuery time-intelligence performance analysis: `SAMEPERIODLASTYEAR` and `DATEADD` are well-optimized in DQ; `DATESYTD`/`TOTALYTD` family are less optimized but still functional. Lead with the well-optimized first.

```dax
Revenue PY =
CALCULATE ( [Total Revenue], SAMEPERIODLASTYEAR ( DIM_CALENDAR[calendar_date] ) )

Revenue YoY $ =
[Total Revenue] - [Revenue PY]

Revenue YoY % =
DIVIDE ( [Revenue YoY $], [Revenue PY] )

Revenue YTD =
TOTALYTD ( [Total Revenue], DIM_CALENDAR[calendar_date] )

Revenue 30-Day MA =
AVERAGEX (
    DATESINPERIOD ( DIM_CALENDAR[calendar_date], MAX ( DIM_CALENDAR[calendar_date] ), -30, DAY ),
    [Total Revenue]
)
```

**Prerequisite for time intelligence:** `DIM_CALENDAR` marked as Date Table (Modeling → Mark as date table → `calendar_date`). Auto Date/Time stays disabled (Project #1 carry-forward).

---

## 3. Page-by-page plan — sessions 5.2 through 5.6

### Session 5.2 — RESET + Demand by Hierarchy + Promotion & Price

**Estimated PBI time: 90-120 min split across before/after backfill prep.**

#### 5.2.A — Architecture reset (do FIRST, before any new page work)

1. Switch storage modes on dims to Dual: in Model view, right-click each of `DIM_ITEM`, `DIM_STORE`, `DIM_CALENDAR` → Properties → Storage mode → Dual. PBI will prompt "this is irreversible" → confirm.
2. Create `_Measures` table: Modeling → New table → paste `_Measures = ROW("Placeholder", BLANK())`. Then in the Fields pane, expand `_Measures`, right-click the Placeholder column → Hide.
3. Re-home or recreate the 4 base measures on `_Measures` per §2.2 formulas. Easiest: create the 4 new measures alongside, rename the OLD ones with `_OLD_` prefix, then in step 4 swap visual references and delete the OLD measures.
4. On Executive Overview page: for each visual (4 KPI cards + dual-axis line chart), click visual → in Visualizations pane drag the OLD measure out of Values, drag the NEW measure in. Verify each card still shows the expected ~$93.8M / 34.5M / 10 / 2.46K (active items max changed semantics, see §2.5 note below). Delete OLD measures from `_Measures` once all visuals re-wired.

**Active Items semantic note:** Old measure was `MAX(active_item_count)` on the mart's per-day rollup, returning peak active items on the busiest day (2.46K). New measure is `DISTINCTCOUNT(item_key)` on the fact across the filter context, which over the full date range returns total distinct items (3,049 if all items have a sale somewhere in the range). If we want to preserve "peak active items on a single day" semantics, the measure becomes:
```dax
Active Items (peak day) =
MAXX ( VALUES ( DIM_CALENDAR[calendar_date] ),
    CALCULATE ( DISTINCTCOUNT ( FACT_DAILY_SALES[item_key] ) )
)
```
Decide which during 5.2.A and document the choice on the page in a text-box footnote.

5. Hide `MART_EXECUTIVE_OVERVIEW` table: in Fields pane right-click the table name → Hide in report view.

#### 5.2.B — Demand by Hierarchy page

Visuals (from north to south):

1. Page title text box: "Demand by Hierarchy" — font 24, top-left.
2. Three slicers row: Date (copy from Executive Overview, sync enabled), State (`DIM_STORE[state_id]`, Vertical list), Category (`DIM_ITEM[cat_id]`, Vertical list). ~120-180 px wide each.
3. Revenue by Category — clustered bar chart. Y-axis: `DIM_ITEM[cat_id]`. X-axis: `[Total Revenue]` (the new fact-based measure). Data labels on. Sort descending by revenue. Place left-half of middle row.
4. Revenue by Department — clustered bar chart. Y-axis: `DIM_ITEM[dept_id]`. X-axis: `[Total Revenue]`. Place right-half of middle row.
5. Hierarchy matrix — full width bottom row. Rows: `cat_id`, `dept_id`, `item_id` (in that order — creates a drill hierarchy). Values: `[Total Revenue]`, `[Total Units Sold]`, `[Revenue Share %]`. Format → Row headers → +/- expand icons on. Default state: collapsed to cat_id only.

#### 5.2.C — Promotion & Price page

Visuals:

1. Page title text box: "Promotion & Price".
2. Three slicers row (same pattern as 5.2.B): Date, State, Category.
3. Avg Selling Price by Category — column chart. X-axis: `DIM_ITEM[cat_id]`. Y-axis: `[Avg Selling Price]`. Place top-half-left of body.
4. Revenue by SNAP Day — donut chart. Legend: a calculated column on `DIM_CALENDAR` called `is_snap_day` (TRUE if any of `snap_ca`/`snap_tx`/`snap_wi` = 1). Values: `[Total Revenue]`. Place top-half-right.
5. Revenue vs Avg Price scatter — scatter chart. X-axis: `[Avg Selling Price]`. Y-axis: `[Total Revenue]`. Legend: `DIM_ITEM[cat_id]`. Details: `DIM_ITEM[dept_id]` (one bubble per dept). Place full-width bottom-half.

### Session 5.3 — Seasonality & Calendar + forecasting research

1. Build Seasonality & Calendar page (slicers, weekend vs weekday revenue comparison, monthly heatmap, holiday-event impact bar). Uses `Weekend Revenue %` + `Holiday Revenue` per §2.4.
2. Forecasting approach decision: Snowflake Cortex ML (current, leans into Snowflake stack) vs Python statsmodels/Prophet (more portable). Lock the choice in this session.

### Session 5.4 — Build forecasting layer end-to-end

1. Train or invoke whatever's chosen in 5.3 → write results back to Snowflake → new `mart_forecast_vs_actual` dbt model joining forecasts to fact at sale_date grain. Tests. Verify SQL artefact `10_phase5_mart_forecast_vs_actual_verification.sql` follows the `04_`–`09_` pattern.

### Session 5.5 — Forecast vs Actual page + time intelligence library

1. Build the fifth page from the new mart. Reuse the page-2-style layout (slicers + visuals).
2. Round out the time intelligence measure library per §2.5.
3. Add dynamic format strings on `Revenue YoY %` (positive green, negative red) — free in Desktop since 2023.

### Session 5.6 — Cross-page polish + closing audit

1. Global cross-page slicer sync (Date + State + Category synced across all 5 pages).
2. Drill-through actions: from Demand by Hierarchy matrix → Item Detail drill-through page. From Promotion & Price scatter → Item Detail.
3. Theme polish via format painter; consistent typography.
4. VertiPaq Analyzer check on dims; if any page's DQ visuals choke (>2s render), evaluate Manage Aggregations on `MART_EXECUTIVE_OVERVIEW` (stretch).
5. POWERBI_PIPELINE.md filled in for sessions 5.2-5.6 walkthrough.
6. 10-point + phase-boundary structural audits. Bundled commit + push closes Phase 5.

---

## 4. Free-tier confirmation — everything we're using is in Desktop free

Verified via Microsoft Learn (Feature availability for Free users, service-features-license-type). Every feature used in this playbook is free in PBI Desktop with no Pro, PPU, or Premium license:

- Composite models (DirectQuery + Dual + Import mix) ✓
- All built-in visuals (bar, column, line, scatter, treemap, matrix, table, card, KPI, slicer, donut) ✓
- Full DAX including time intelligence (SAMEPERIODLASTYEAR, DATEADD, TOTALYTD, etc.) ✓
- Calculated tables/columns/measures ✓
- Drill-through pages, bookmarks, field parameters ✓
- Dynamic format strings ✓
- Sync slicers across pages ✓
- Themes, format painter, conditional formatting ✓

Not used (out of scope, mostly Service-side): scheduled refresh, gateways, dataflows, deployment pipelines, paginated reports, XMLA endpoint, incremental refresh execution, Copilot-in-Service.

---

## 5. Discipline rules — to prevent recurrence of the 5.2 mistakes

These are operational rules that must be followed in every Phase 5 session. Drafted in response to mistakes hit during session 5.2:

1. **Before prescribing any PBI step, verify state.** If unsure whether a measure exists, a relationship is active, a column has a specific name — ASK or web-check. Never assume from prior session's closeout text; sessions can drift from documentation.
2. **Measures live on `_Measures` table only. Never on data tables.** If a measure ends up homed elsewhere, move it.
3. **Measures aggregate `FACT_DAILY_SALES`. Never the mart.** The mart is hidden in PBI; if a formula references a mart column, it's wrong.
4. **Dims joined to a DirectQuery fact must be in Dual storage mode.** Import is a downgrade.
5. **When dragging a field into a visual, use the named measure from `_Measures`, never a raw column.** Implicit `Sum of <column>` aggregations are a red flag in code review.
6. **UI walkthroughs: 1-2 steps default, 3-4 max when the user is BI-experienced.** Stop and wait for confirmation. Skip basic visualization explanations.
7. **For destructive PBI changes (delete measure, change storage mode, hide table): explain the rollback path first.**

---

## 6. Session 5.2 reset checklist (for when Phil resumes after break)

Do these in order. Don't skip steps.

- [ ] Read §1 (locked decisions) and §3.5.2.A (reset sub-steps) before touching PBI.
- [ ] Switch `DIM_ITEM`, `DIM_STORE`, `DIM_CALENDAR` to Dual mode in Model view (3 tables × 1 click each).
- [ ] Create `_Measures` table via Modeling → New table.
- [ ] Hide the Placeholder column on `_Measures`.
- [ ] Rename the 4 existing measures with `_OLD_` prefix (or just delete them after step below if comfortable).
- [ ] Create 4 new fact-based measures per §2.2 on `_Measures`.
- [ ] On Executive Overview page: re-wire each visual to use new measures (4 cards + 1 line chart).
- [ ] Delete the 4 `_OLD_` measures once all visuals confirmed working.
- [ ] Hide `MART_EXECUTIVE_OVERVIEW` from report view.
- [ ] Verify Executive Overview page still renders correctly (cards show ~$93.8M / 34.5M / 10 / 3,049 or 2.46K depending on Active Items semantic choice).
- [ ] **Only then proceed to §3.5.2.B Demand by Hierarchy.**

---

## Sources

Backing research conducted 2026-05-18 during session 5.2 reset. Authoritative web sources:

- [Use composite models in Power BI Desktop — Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/transform-model/desktop-composite-models)
- [Composite model guidance — Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/guidance/composite-model-guidance)
- [DirectQuery model guidance — Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/guidance/directquery-model-guidance)
- [Table storage mode in Power BI Semantic Models — Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/transform-model/desktop-storage-mode)
- [Understand star schema and the importance for Power BI — Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/guidance/star-schema)
- [Feature availability for Free users in Power BI service — Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/fundamentals/end-user-features)
- [Drillthrough in Power BI reports — Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/create-reports/desktop-drillthrough)
- [Slicers in Power BI — Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/visuals/power-bi-visualization-slicers)
- [Field parameters — Microsoft Learn](https://learn.microsoft.com/en-us/power-bi/create-reports/power-bi-field-parameters)
- [Regular and limited relationships in Power BI — SQLBI](https://www.sqlbi.com/articles/strong-and-weak-relationships-in-power-bi/)
- [Performance of limited and regular relationships — SQLBI](https://www.sqlbi.com/articles/analyzing-the-performance-of-limited-and-regular-relationships/)
- [Optimizing time intelligence in DirectQuery — SQLBI](https://www.sqlbi.com/articles/optimizing-time-intelligence-in-directquery/)
- [Composite models whitepaper — SQLBI](https://www.sqlbi.com/topics/composite-models/?type=whitepaper)
- [Impact of calendar-based time intelligence on DirectQuery performance — Chris Webb, Nov 2025](https://blog.crossjoin.co.uk/2025/11/30/a-look-at-the-impact-of-calendar-based-time-intelligence-on-power-bi-directquery-performance/)
- [Composite model in Power BI — RADACAD](https://radacad.com/composite-model-directquery-and-import-data-combined-evolution-begins-in-power-bi/)
- [Power BI November 2025 Feature Summary — Microsoft Power BI Blog](https://powerbi.microsoft.com/en-us/blog/power-bi-november-2025-feature-summary/)
- [DAX Guide — dax.guide](https://dax.guide)

---

*This document is the single source of truth for the Power BI portion of Phase 5. If Claude proposes a step that conflicts with anything here, Phil should push back and ask Claude to either justify the deviation or correct course.*
