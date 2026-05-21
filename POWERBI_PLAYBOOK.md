# POWERBI_PLAYBOOK.md — Sessions 5.2 → 5.6 Locked Plan

> **Purpose.** Single source of truth for the Power BI build through end-of-Phase-5.
>
> **Revision history.** Originally drafted 2026-05-18 (Phase 5 session 5.2). **Substantially rewritten 2026-05-19 (Phase 5 session 5.3)** after deep-research audit found two issues with the original plan: (a) Import → Dual is a one-way restriction in PBI Desktop, making the original "promote dims to Dual" step impossible without re-importing as DirectQuery first; (b) exposing a 32.9M-row fact via DirectQuery as the primary semantic surface for a 5-page dashboard is not the professional pattern. Resolved by pivoting to an all-Import architecture with two user-defined aggregations + a new forecast fact landed by Snowflake Cortex ML.
>
> **How to use.** Read top-to-bottom at the start of every Phase 5 session. Each session's step list is meant to be followed exactly. The architectural decisions in §1 are LOCKED; do not relitigate them unless evidence forces it.

---

## 1. Locked architectural decisions

### 1.1 Storage modes — all Import, fact columns pruned at load

| Table | Storage | Visible? | Reason |
|---|---|---|---|
| `FACT_DAILY_SALES` | **Import** | Hidden (measures only) | Pruned columns; VertiPaq compresses comfortably toward / under 100 MB |
| `FACT_FORECAST_DAILY` | **Import** | Hidden | New 28-day forecast fact (~85K rows) |
| `AGG_SALES_DAILY` | **Import** | Hidden, wired as user-defined aggregation | Day-grain rollup of `FACT_DAILY_SALES` |
| `AGG_SALES_DAILY_ITEM_CAT` | **Import** | Hidden, wired as user-defined aggregation | Day × cat_id rollup |
| `MART_FORECAST_VS_ACTUAL` | **Import** | Visible (powers the Forecast vs Actual page directly) | UNION of actuals + forecast with `series_type` discriminator |
| `DIM_CALENDAR` | **Import** | Visible, **marked as Date Table** | Conformed dim |
| `DIM_ITEM` | **Import** | Visible | Conformed dim |
| `DIM_STORE` | **Import** | Visible | Conformed dim |
| `_Measures` | n/a | Visible | DAX measure home |

**No DirectQuery. No Dual. No composite mode.** The Storage-mode lock that blocked the 2026-05-18 plan is bypassed entirely by never loading anything as non-Import in the first place. Re-importing as Import via the Snowflake connector at PBI build time gives a clean slate.

**Fact column pruning at PBI Import time — UPDATED 2026-05-20 (Phase 5.4).** In Power Query before loading, drop `sale_key` ONLY (32-char MD5 hash with 32.9M unique values — the actual compression killer in VertiPaq). **Keep `date_key`** — VertiPaq dictionary-encodes it efficiently (only ~1,180 distinct values, ~50MB total footprint) and it's needed for clean relationships and downstream UDA wiring (kept for option-preservation even though §1.4 ruled UDA out for this build). Optionally drop `sell_price` only if `.pbix` size is borderline. Keep: `item_id`, `store_id`, `sale_date`, `date_key`, `units_sold`, `revenue_amount_usd`, `item_key`, `store_key`.

**Why `date_key` is NOT a compression killer (corrected from original §1.1).** The original playbook claimed `date_key` should be dropped because it was "redundant once `sale_date` is on the table." That reasoning conflated row count with distinct-value count. VertiPaq's dictionary encoding cost scales with distinct values, not row count. `sale_key` has 32.9M distinct values (one per fact row) so dictionary + 32.9M pointers = the actual size hit. `date_key` has ~1,180 distinct values (one per date) so dictionary + 32.9M short-int pointers = negligible. Keep it.

### 1.2 Measure layer — dedicated hidden `_Measures` table

All measures live on a single empty hidden table called `_Measures`. Convention enforced by Microsoft Learn + SQLBI. Reasons:

- Measures don't need a data home — they're computed expressions.
- Dedicated table sorts alphabetically to the top of the field list (leading underscore).
- Refactoring is trivial because measures have no data-table home.

**How to create:** Modeling tab → New table → `_Measures = ROW("Placeholder", BLANK())`. Hide the Placeholder column.

### 1.3 Single measure family sourced from `FACT_DAILY_SALES`; aggregations transparently accelerate

All measures aggregate `FACT_DAILY_SALES`. The two `AGG_*` tables are wired in Power BI via **Manage Aggregations** so that when a visual asks for "revenue by date" or "revenue by category", PBI rewrites the query against the appropriate agg table automatically. Measures stay simple; performance is fast; the model is interview-defensible as the canonical Microsoft pattern.

Senior-DE talk track: *"I built a Kimball star in `warehouse` and two pre-aggregated rollups in `marts`, wired as managed aggregations. Power BI transparently routes summary queries to the rollups and falls through to the fact for detail queries."*

### 1.4 Aggregate tables — UDA path ABANDONED 2026-05-20 (kept in dbt+Snowflake as portfolio narrative only)

**UPDATED 2026-05-20 (Phase 5.4).** Manage Aggregations is architecturally incompatible with the all-Import storage-mode decision locked in §1.1. Microsoft Learn (`aggregations-advanced`) requires that **the Detail Table for any user-defined aggregation be in DirectQuery storage mode**, not Import. Our entire model is Import, so UDA cannot be wired. The two architectural choices are mutually exclusive — you can have all-Import simplicity OR user-defined aggregations, not both.

**What this means in practice.** The two aggregate tables still exist:

- `AGG_SALES_DAILY` — day-grain rollup (~1.1K rows) in `RETAIL_DB.MARTS`.
- `AGG_SALES_DAILY_ITEM_CAT` — day × cat_id rollup (~3.4K rows) in `RETAIL_DB.MARTS`.

They live in dbt + Snowflake as portfolio-narrative artefacts ("I built two pre-aggregated marts following the Kimball aggregate pattern"). They are **NOT loaded into the PBI semantic model**. All PBI measures hit `FACT_DAILY_SALES` directly. Empirically: VertiPaq Import compresses the 32.9M-row fact to ~60-80MB and Sum-based measures return sub-second, so the performance loss from not having UDA is negligible at our scale.

**Interview talk track**: *"I went all-Import for the semantic model because the alternative — DirectQuery on the fact + Dual on the dims — has a documented one-way restriction in PBI Desktop. The trade-off was losing access to user-defined aggregations, which require a DirectQuery detail table. I kept the pre-aggregated marts in dbt for the architectural story but didn't wire them into PBI — VertiPaq compression on the Import-mode fact made the perf gap negligible at our scale."*

**For Phase C build**: do NOT include the agg tables in the PBI Get Data table selection. Pick 6 tables: 3 dims + FACT_DAILY_SALES + FACT_FORECAST_DAILY + MART_FORECAST_VS_ACTUAL. (Original §6 Phase C checklist listed 8 — that's superseded by this 2026-05-20 patch.)

### 1.5 Forecast layer — Snowflake Cortex ML, item-level grain

Forecasting lives in the data layer, not in DAX. Pipeline:

1. `int_forecast_input` (dbt intermediate view) — slim three-column view (series_id = item_id, sale_date, units_sold). Item-level grain — units summed across stores per item. ~3K series × ~1,150 days = ~3.4M training rows.
2. `sql/snowflake/05_train_forecast_model.sql` — Snowsight script. Creates `SNOWFLAKE.ML.FORECAST` model object (`retail_demand_forecast_28d`), calls `FORECAST(28)`, lands raw output to `RETAIL_DB.INTERMEDIATE.FORECAST_RAW_OUTPUT`. Trains in ~3-5 min on XS warehouse.
3. `fact_forecast_daily` (dbt warehouse model) — conforms keys to the warehouse star (`item_key`, `date_key`, surrogate `forecast_key`), denormalises `forecast_revenue_usd` via recent-price join, floors negatives at 0.
4. `mart_forecast_vs_actual` (dbt mart) — UNIONs actuals and forecasts at item × day grain with a `series_type` discriminator. Powers the Forecast vs Actual PBI page directly.

**Grain decision — item-level not item × store.** Aggregating units across stores produces stronger per-series signal because each item's daily demand across all 10 stores is more stationary than per-store splits. Standard retail forecasting pattern when stores share similar SKU mixes. Also trains in a tolerable wall-clock on XS warehouse (3-5 min vs 2-5 hours at item × store).

**Forecast horizon known gap.** `dim_calendar` currently ends 2014-03-22; forecast dates run 2014-03-23 → 2014-04-19. `date_key` on `fact_forecast_daily` and `mart_forecast_vs_actual` will not have matches in `dim_calendar` until the calendar is extended. Phase 5.6 follow-up: extend `dim_calendar` to cover the forecast horizon for clean PBI date slicing across both facts.

---

## 2. Measure inventory

### 2.1 Base measures (4 — built on `_Measures`, source `FACT_DAILY_SALES`)

```dax
Total Revenue =
SUM ( FACT_DAILY_SALES[revenue_amount_usd] )

Total Units Sold =
SUM ( FACT_DAILY_SALES[units_sold] )

Active Stores =
DISTINCTCOUNT ( FACT_DAILY_SALES[store_key] )

Active Items =
VAR LatestDate = MAX ( DIM_CALENDAR[calendar_date] )
RETURN
    CALCULATE (
        DISTINCTCOUNT ( FACT_DAILY_SALES[item_key] ),
        DIM_CALENDAR[calendar_date] = LatestDate
    )
```

Format: `Total Revenue` as `$#,0`, `Total Units Sold` as `#,0`, counts as whole numbers.

**Active Items semantic — LOCKED 2026-05-19.** Returns distinct items selling AS AT the latest date in the current filter context. Answers "how many SKUs are active right now?" — most intuitive read for an exec card.

### 2.2 Page-specific measures — Demand by Hierarchy + Promotion & Price

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

**`SNAP Day Revenue` deleted from the model 2026-05-21 (Phase 5 session 5.6 close).** The Promotion & Price donut was built using the `is_snap_day` calculated column on `DIM_CALENDAR` as Legend + `Total Revenue` as Values — equally valid build pattern, makes the dedicated `SNAP Day Revenue` measure redundant. DAX retained here in the playbook for reference / future re-creation if a Card-style "SNAP vs non-SNAP" split is wanted later.

### 2.3 Seasonality & Calendar measures

```dax
Weekend Revenue % =
DIVIDE (
    CALCULATE ( [Total Revenue], DIM_CALENDAR[is_weekend] = TRUE ),
    [Total Revenue]
)

Holiday Revenue =
CALCULATE ( [Total Revenue], DIM_CALENDAR[is_holiday] = TRUE )
```

**`Weekend Revenue %` deleted from the model 2026-05-21 (Phase 5 session 5.6 close).** The Seasonality & Calendar weekend-vs-weekday comparison was built as a 2-bar column chart with `IS_WEEKEND` on the X-axis and `Total Revenue` on the Y-axis — the chart itself surfaces the split visually, making the dedicated percentage measure redundant. DAX retained for reference; recreate if a KPI-card-style "Weekend Revenue %" pill is ever wanted.

### 2.4 Forecast vs Actual measures (new, source `MART_FORECAST_VS_ACTUAL`)

```dax
Actual Units =
CALCULATE (
    SUM ( MART_FORECAST_VS_ACTUAL[units] ),
    MART_FORECAST_VS_ACTUAL[series_type] = "actual"
)

Forecast Units =
CALCULATE (
    SUM ( MART_FORECAST_VS_ACTUAL[units] ),
    MART_FORECAST_VS_ACTUAL[series_type] = "forecast"
)

Actual Revenue =
CALCULATE (
    SUM ( MART_FORECAST_VS_ACTUAL[revenue_usd] ),
    MART_FORECAST_VS_ACTUAL[series_type] = "actual"
)

Forecast Revenue =
CALCULATE (
    SUM ( MART_FORECAST_VS_ACTUAL[revenue_usd] ),
    MART_FORECAST_VS_ACTUAL[series_type] = "forecast"
)

Forecast Upper 95 =
CALCULATE (
    SUM ( MART_FORECAST_VS_ACTUAL[units_upper_95] ),
    MART_FORECAST_VS_ACTUAL[series_type] = "forecast"
)

Forecast Lower 95 =
CALCULATE (
    SUM ( MART_FORECAST_VS_ACTUAL[units_lower_95] ),
    MART_FORECAST_VS_ACTUAL[series_type] = "forecast"
)

Total Units (Mart) =
SUM ( MART_FORECAST_VS_ACTUAL[UNITS] )

Total Revenue (Mart) =
SUM ( MART_FORECAST_VS_ACTUAL[REVENUE_USD] )
```

**Added 2026-05-21 (Phase 5 session 5.6).** `Total Units (Mart)` and `Total Revenue (Mart)` are the mart-sourced equivalents of the fact-sourced §2.1 measures. They exist specifically so the Forecast vs Actual matrix can split by `series_type` (a column that lives on `MART_FORECAST_VS_ACTUAL` but NOT on `FACT_DAILY_SALES`). Naming pattern: same metric name + `(Mart)` suffix. Pattern carries forward to any future "actual vs forecast" or "current vs prior" mart-style scenario.

### 2.5 Time intelligence measures (5 — Phase 5.5)

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

**Prerequisite:** `DIM_CALENDAR` marked as Date Table on `calendar_date`. Auto Date/Time stays disabled.

---

## 3. Page-by-page plan

### 3.1 Executive Overview

- Title text box.
- Date slicer on `DIM_CALENDAR[calendar_date]`, Between mode.
- 4 KPI cards: Total Revenue, Total Units Sold, Active Stores, Active Items.
- Dual-axis line chart: Total Revenue + Total Units Sold across `calendar_date`.

### 3.2 Demand by Hierarchy

- Title.
- Slicers: Date (sync from Executive Overview), State (`DIM_STORE[state_id]`), Category (`DIM_ITEM[cat_id]`).
- Revenue by Category — clustered bar chart, Y=cat_id, X=Total Revenue, sort desc, data labels on.
- Revenue by Department — clustered bar chart, Y=dept_id, X=Total Revenue.
- Hierarchy matrix — rows cat_id → dept_id → item_id; values Total Revenue + Total Units Sold + Revenue Share %; default collapsed to cat_id.

### 3.3 Promotion & Price

- Title.
- Same 3 slicers as 3.2.
- Avg Selling Price by Category — column chart, X=cat_id, Y=Avg Selling Price.
- Revenue by SNAP Day — donut chart. Requires calculated column `is_snap_day` on `DIM_CALENDAR` (TRUE if any of snap_ca/snap_tx/snap_wi = 1). Legend=is_snap_day, Values=Total Revenue.
- Revenue vs Avg Price scatter — X=Avg Selling Price, Y=Total Revenue, Legend=cat_id, Details=dept_id.

### 3.4 Seasonality & Calendar

- Title.
- Slicers: Date, State, Category.
- Weekend vs Weekday comparison — bar chart using `Weekend Revenue %` + manual is_weekend split.
- Monthly heatmap — matrix with Year (rows) × Month (cols), values=Total Revenue, conditional formatting on data bars or background.
- Holiday event impact — bar chart, X=`DIM_CALENDAR[event_name_1]`, Y=`Holiday Revenue`.

### 3.5 Forecast vs Actual

- Title.
- Date slicer extended to cover forecast horizon (requires `dim_calendar` extension — see §1.5).
- Category slicer.
- Line chart: Actual Revenue + Forecast Revenue across `observation_date`. Both lines on same axis. Forecast line styled differently (dashed).
- Confidence-interval ribbon: shaded area between `Forecast Lower 95` and `Forecast Upper 95` — use a stacked area chart trick or the Power BI ribbon chart.
- Forecast vs Actual matrix: rows=cat_id; columns=series_type ('actual', 'forecast'); values=`Total Units (Mart)`, `Total Revenue (Mart)`. **Important** — these mart-sourced measures (`SUM(MART_FORECAST_VS_ACTUAL[UNITS])` / `SUM(MART_FORECAST_VS_ACTUAL[REVENUE_USD])`) are REQUIRED here; the fact-sourced `Total Units Sold` / `Total Revenue` from §2.1 cannot be filtered by `series_type` because `FACT_DAILY_SALES` has no `series_type` column. Both columns of the matrix would render the same total. The `(Mart)` suffix naming convention disambiguates the two same-metric / different-source measures in the field list. Locked 2026-05-21 (Phase 5 session 5.6).

---

## 4. Free-tier confirmation

Verified via Microsoft Learn. Every feature in this playbook is free in PBI Desktop with no Pro / PPU / Premium license:

- Import storage mode + composite models ✓
- All built-in visuals ✓
- Full DAX including time intelligence ✓
- Calculated tables / columns / measures ✓
- User-defined aggregations (Manage Aggregations) ✓
- Drill-through pages, bookmarks, field parameters ✓
- Dynamic format strings ✓
- Sync slicers across pages ✓

---

## 5. Discipline rules

These are operational rules that must be followed in every Phase 5 session.

1. **Before prescribing any PBI step, verify state.** If unsure whether a measure exists, a relationship is active, a column has a specific name — ASK or web-check. Never assume from prior session's closeout text.
2. **Measures live on `_Measures` only. Never on data tables.** If a measure ends up homed elsewhere, move it.
3. **Measures aggregate `FACT_DAILY_SALES` or `MART_FORECAST_VS_ACTUAL`.** Never raw columns on aggs (PBI's UDA layer routes for you).
4. **Everything Import.** No DirectQuery, no Dual. If a recommendation requires non-Import storage mode, push back.
5. **When dragging a field into a visual, use the named measure from `_Measures`, never a raw column.** Implicit `Sum of <column>` aggregations are a red flag.
6. **UI walkthroughs: 1-2 steps default, 3-4 max when the user is BI-experienced.** Stop and wait for confirmation.
7. **For destructive PBI changes (delete table, delete measure, change storage mode): explain the rollback path first.**
8. **Communicate runtime expectations BEFORE starting any operation > 5 minutes.** Explicit time estimate up front; any operation that ends up > 2× the estimate is a triggered post-mortem.

---

## 6. Clean rebuild checklist (Phase 5.3 onwards)

Do these in order. Don't skip steps.

**Phase A — dbt rebuild (out of PBI).**

- [x] Step 1: Rename `mart_executive_overview` → `agg_sales_daily`, add `date_key`. *(done 2026-05-19)*
- [x] Step 2: Build `agg_sales_daily_item_cat` mart. *(done 2026-05-19)*
- [x] Step 3a: Build `int_forecast_input` view. *(done 2026-05-19)*
- [ ] Step 3b: Run `sql/snowflake/05_train_forecast_model.sql` in Snowsight (~3-5 min). Verify smoke test: ~85K forecast rows, ~3K series, dates 2014-03-23 → 2014-04-19.
- [ ] Step 3c: `dbt build --select fact_forecast_daily` — conforms keys + adds revenue forecast.
- [ ] Step 3d: `dbt build --select mart_forecast_vs_actual` — UNION of actuals + forecast.
- [ ] Step 4: `dbt build` full project — verify PASS=all green.

**Phase B — Snowflake verification SQL.**

- [ ] Write `sql/verify/10_phase5_forecast_layer_verification.sql` (5-section PASS/FAIL on forecast input, raw output, fact, mart).
- [ ] Run section-by-section in Snowsight; all PASS.

**Phase C — Power BI semantic model rebuild.**

- [ ] Open `retail_demand_forecasting.pbix`.
- [ ] Delete all 5 currently-loaded tables (DIM_CALENDAR, DIM_ITEM, DIM_STORE, FACT_DAILY_SALES, MART_EXECUTIVE_OVERVIEW). Pages + slicers + visuals stay (will rebind when measures exist).
- [ ] Get Data → Snowflake → connect with POWERBI_READER role. Choose Import mode for ALL tables.
- [ ] Select: AGG_SALES_DAILY, AGG_SALES_DAILY_ITEM_CAT, DIM_CALENDAR, DIM_ITEM, DIM_STORE, FACT_DAILY_SALES, FACT_FORECAST_DAILY, MART_FORECAST_VS_ACTUAL.
- [ ] In Power Query, on `FACT_DAILY_SALES`: drop `sale_key`, `date_key` columns (pruning for size). Optionally drop `sell_price` if size needs trimming.
- [ ] Apply / Load.
- [ ] Verify .pbix file size < 100 MB.
- [ ] Manage Relationships: build 7 relationships (see §1.1 table; fact dims → 3 dims, forecast fact dims → 3 dims minus dim_calendar, mart dims → item + calendar).
- [ ] Mark `DIM_CALENDAR` as Date Table on `calendar_date`.
- [ ] Create `_Measures` table (Modeling → New table → `_Measures = ROW("Placeholder", BLANK())`). Hide Placeholder column.
- [ ] Recreate all measures from §2 on `_Measures`.
- [ ] Manage Aggregations: register `AGG_SALES_DAILY` (precedence 50, summary table behind FACT_DAILY_SALES) and `AGG_SALES_DAILY_ITEM_CAT` (precedence 30). Map every column.
- [ ] Hide: FACT_DAILY_SALES, FACT_FORECAST_DAILY, AGG_SALES_DAILY, AGG_SALES_DAILY_ITEM_CAT.
- [ ] Verify Executive Overview page renders correctly with the new measures.

**Phase D — Page builds.**

- [ ] Execute §3.1-§3.5 in order. Each page uses the §2 measures.

**Phase E — Polish + commit.**

- [ ] Cross-page slicer sync (Date + State + Category).
- [ ] Drill-through actions (Demand by Hierarchy → Item Detail; Promotion & Price → Item Detail).
- [ ] Theme polish.
- [ ] VertiPaq Analyzer check on dims.
- [ ] Phase-boundary structural audit + bundled commit.

---

## Sources

Backing research:

- [Microsoft Learn — Table storage mode in Power BI semantic models](https://learn.microsoft.com/en-us/power-bi/transform-model/desktop-storage-mode) (proves Import → Dual is one-way)
- [Microsoft Learn — User-defined aggregations](https://learn.microsoft.com/en-us/power-bi/transform-model/aggregations-advanced)
- [Microsoft Learn — Composite model guidance](https://learn.microsoft.com/en-us/power-bi/guidance/composite-model-guidance)
- [Microsoft Learn — Star schema](https://learn.microsoft.com/en-us/power-bi/guidance/star-schema)
- [Microsoft Learn — Data reduction techniques for Import modeling](https://learn.microsoft.com/en-us/power-bi/guidance/import-modeling-data-reduction)
- [Snowflake Docs — Time-series forecasting (ML functions)](https://docs.snowflake.com/en/user-guide/ml-functions/forecasting)
- [Snowflake Docs — CREATE SNOWFLAKE.ML.FORECAST](https://docs.snowflake.com/en/sql-reference/classes/forecast/commands/create-forecast)
- [phData — Retail sales forecasting with Snowflake Cortex ML](https://www.phdata.io/blog/store-sales-forecasting-with-snowflake-cortex-ml-and-snowpark/)
- [dbt Developer Hub — Marts: business-defined entities](https://docs.getdbt.com/best-practices/how-we-structure/4-marts)
- [dbt Labs — Complete guide to dimensional modeling](https://www.getdbt.com/blog/guide-to-dimensional-modeling)
- [SQLBI — Strong and weak relationships in Power BI](https://www.sqlbi.com/articles/strong-and-weak-relationships-in-power-bi/)
- [IntelliTect — Power BI data compression](https://intellitect.com/blog/power-bi-data-compression/)
- [Tabular Editor — User-defined aggregations](https://docs.tabulareditor.com/tutorials/user-defined-aggregations.html)
- [Fabric Community — Power BI storage mode greyed out](https://community.fabric.microsoft.com/t5/Desktop/Power-BI-storage-mode-greyed-out/td-p/3625944)

---

*Revised 2026-05-19. Single source of truth for the Power BI portion of Phase 5. If Claude proposes a step that conflicts with anything here, Phil should push back.*
