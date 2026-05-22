# POWERBI_PIPELINE.md — Power BI Dashboard Walkthrough

> Companion to `EXTRACT_PIPELINE.md` and `DBT_PIPELINE.md`. This doc explains
> the Power BI layer that consumes the dbt-built `WAREHOUSE` star schema and
> `MARTS` forecast layer to surface a five-page analyst-facing dashboard.
>
> Last updated: 2026-05-22 (Phase 5 session 5.9 close — Phase 5 COMPLETE).
>
> The locked source of truth for the PBI build is `POWERBI_PLAYBOOK.md`
> (revised 2026-05-19, patched through 5.9). This walkthrough doc is the
> portfolio-facing narrative; the playbook is the operational checklist.

---

## What Power BI does in this project

Power BI is the consumption layer that closes the end-to-end story: Azure SQL →
Snowflake `RAW` → dbt-built `STAGING` / `INTERMEDIATE` / `WAREHOUSE` / `MARTS` →
**Power BI Desktop dashboard**. The pipeline produces an analytical model in
Snowflake; Power BI turns it into a five-page business-facing dashboard that
operations and S&OP stakeholders can use to answer demand-planning questions.

**Mental model.** Power BI is the *retail clerk on a tour* of the Snowflake
warehouse. It walks in with a read-only badge (`POWERBI_READER`), reads the
shelves it's allowed to see (`WAREHOUSE.fact_*` + `dim_*` + `MARTS.mart_*`),
and renders what it sees into visuals. It never builds, restocks, or moves
anything — all that happens upstream in dbt. Pretty labels, derived columns,
and business-logic transformations live in dbt, not DAX. The only Power-Query
work in this model is a tiny `Text.Proper` text-case transformation on one
mart column (see §6 below) — everything else is a pull-through from Snowflake.

---

## Architecture position

```
RETAIL_DB.RAW          ← Airflow extract (Phase 2-3)
        ↓
RETAIL_DB.STAGING      ← dbt staging (Phase 4)
        ↓
RETAIL_DB.INTERMEDIATE ← dbt intermediate (Phase 4)
        ↓
RETAIL_DB.WAREHOUSE    ← dbt warehouse — Kimball star (Phase 4)
        ↓
RETAIL_DB.MARTS        ← dbt marts — forecast layer (Phase 4-5)
        ↓
Power BI Desktop       ← THIS DOC (Phase 5)
        ↓
Five-page dashboard    ← Phase 5 sessions 5.1 – 5.9
```

Power BI connects to Snowflake via the **native Snowflake connector** under
the dedicated **`POWERBI_READER`** role (least-privilege; see
`sql/snowflake/04_grant_powerbi_reader.sql`). The semantic model is **all-Import**:
all six tables (1 fact + 1 forecast mart + 4 dims) load into PBI's in-memory
VertiPaq engine at refresh time. No DirectQuery, no composite, no
user-defined aggregations — the architectural arc that led to this lock is
documented in §5 below.

---

## Snowflake connection

Power BI Desktop connects to Snowflake via the **native Snowflake connector**
(`Get Data → More → Snowflake`). Three fields configure the connection:

- **Server**: `<account_locator>.<region>.snowflakecomputing.com`. For this
  project: `tq94402.ap-southeast-2.snowflakecomputing.com` (AWS Sydney region,
  surfaced via `SELECT CURRENT_ACCOUNT(), CURRENT_REGION();` in Snowsight).
- **Warehouse**: `WH_RETAIL` — the XSMALL compute warehouse provisioned in
  Phase 2. Auto-resumes on connection, auto-suspends after 60s idle.
- **Advanced Options → Role name**: `POWERBI_READER` — pins the session to
  the least-privilege read-only role at the connection level. Critical:
  without this, PBI falls back to the user's default role
  (`RETAIL_ENGINEER`), which has full ownership of `WAREHOUSE` + `MARTS`.
  Pinning the role makes the principle-of-least-privilege story enforceable.

**`POWERBI_READER` role** is provisioned by
`sql/snowflake/04_grant_powerbi_reader.sql`. It grants:

- `USAGE` on `WH_RETAIL` (run queries, no `OPERATE`)
- `USAGE` on `DATABASE RETAIL_DB` (see in metadata, no `CREATE SCHEMA`)
- `USAGE` + `SELECT` (existing + future tables/views) on
  `RETAIL_DB.WAREHOUSE` and `RETAIL_DB.MARTS`
- Explicitly NO grants on `RAW` / `STAGING` / `INTERMEDIATE` — Power BI
  never sees the kitchen prep

Granted to user `PHELUCIAM` as a second role alongside `RETAIL_ENGINEER`
(reuse-existing-user pattern; service-account separation deferred to
Project #3 if needed). The connection string's role pin scopes PBI's queries
to read-only even though the underlying user can switch roles in Snowsight.

**Verification**: `SHOW GRANTS TO ROLE POWERBI_READER` returns only `USAGE`
+ `SELECT` rows — no `INSERT/UPDATE/DELETE/TRUNCATE/CREATE`. Negative test
(commented at the bottom of the SQL file) —
`SELECT COUNT(*) FROM RETAIL_DB.RAW.M5_SALES_TRAIN` under POWERBI_READER
returns **"Object does not exist or not authorized"** — the boundary
genuinely bites.

### Gotcha #1 — schema visibility ≠ access boundary

PBI's Navigator initially showed all 7 schemas in `RETAIL_DB` (including
`RAW`/`STAGING`/`INTERMEDIATE`) under `POWERBI_READER`. Looked like a
privilege leak. Diagnosed via
`INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER('PHELUCIAM')` — confirmed every PBI
metadata query ran under `POWERBI_READER`. The schema listing is Snowflake's
standard metadata behavior: `SHOW SCHEMAS IN DATABASE` returns all schemas
in a database the role has DB-level `USAGE` on, regardless of per-schema
privileges. `USAGE` on the schema controls whether you can OPEN it; metadata
visibility is broader. See `LEARNINGS.md` →
"2026-05-18 — Snowflake metadata visibility ≠ access boundary" for the
visitor-badge analogy.

### Gotcha #2 — credential desync after editing data source settings

First re-connect attempt after editing data source settings failed with
`ODBC: 260002 Password is empty`. Root cause: PBI saves credentials
per-server separately from connection settings; editing one without
re-entering the other desyncs them. Fix:
`File → Options → Data source settings → Clear Permissions + Delete →
reconnect from scratch with auth re-entered`.

---

## Storage mode decision — the architectural arc

The final answer is **all-Import**, with all six tables loaded into PBI's
in-memory VertiPaq engine at refresh time. Getting there took four sessions
and three architectural pivots. Documenting the arc here because the
intermediate decisions are part of the portfolio story — each pivot was
forced by a real constraint, not a preference.

### Phase A (session 5.1) — full Import

Initial decision was straightforward: small mart on the Executive Overview
page, three small dims (1,082 + 3,049 + 10 rows), one ~33M-row fact. Loaded
the fact over residential internet in ~10 minutes into VertiPaq. Worked.

### Phase B (session 5.2) — composite mode forced by `.pbix` file size

The resulting `.pbix` was **949 MB** — VertiPaq compressed the row data
fine, but the model file still exceeded GitHub's **100 MB per-file push
limit**. The git-push attempt failed loudly. Pivoted to **composite mode**:

- **DirectQuery** on `FACT_DAILY_SALES` (32.9M rows stay in Snowflake,
  queries fire on demand for fact-driven visuals)
- **Import** on the mart + 3 dims (small tables, instant interactivity)

Result: `.pbix` dropped to **264 KB** (a ~3,600× reduction), pushes cleanly
without LFS. Felt like a senior-DE composite-mode pattern landing as the
real interview talk-track.

**Mechanics gotcha**: PBI Desktop **cannot change a table's storage mode
from Import to DirectQuery via the Properties pane dropdown**. The dropdown
greys the option out by design (Import unlocks features DirectQuery
doesn't support; the conversion is one-way). The path is **delete the
table from the model**, then **re-add via Get Data and choose DirectQuery
at the load dialog**. Relationships are lost on delete and must be rebuilt.

### Phase C (session 5.3-5.4) — UDA detour

Composite was working but every fact-driven visual fired a fresh Snowflake
query. Looked into **User-Defined Aggregations (UDA / Manage Aggregations)**
as a way to add Import-mode aggregate tables that PBI would auto-route
queries to when grain permitted, falling back to DirectQuery for detail.
Built two aggregate marts in dbt for the experiment:
`agg_sales_daily` (1,081 rows) and `agg_sales_daily_item_cat` (3,243 rows).

Microsoft Learn then surfaced the killer constraint: **UDA requires the
detail table to be in DirectQuery storage mode.** The aggregation feature
is architecturally incompatible with an all-Import model. The all-Import
+ UDA combination doesn't exist.

**Decision**: keep the agg marts in dbt as portfolio narrative artefacts
("I built two pre-aggregated marts following the Kimball aggregate pattern,
then learned UDA requires DirectQuery on the detail table — incompatible
with all-Import — so kept the marts for the architectural story but didn't
wire them into PBI"). Adds ~5-10 seconds to `dbt build`, negligible cost
for the talk-track value.

### Phase D (session 5.4 onwards) — back to all-Import, lean

Composite-mode latency was sluggish for the 5.2-5.4 slicing pages (every
slicer click fired a fresh Snowflake query). With UDA off the table, the
remaining options were:

- Keep composite, accept the latency
- Switch back to all-Import and find another way to manage the 949 MB

Chose **all-Import with column pruning**. Trimmed `FACT_DAILY_SALES` at
load time to only the columns the dashboard actually uses (dropped raw
event flags + a handful of staging-era passthrough columns). VertiPaq's
columnar compression on the trimmed fact + 60-day forecast horizon brought
the `.pbix` to a manageable size for the repo (saved with Git LFS rather
than the 100 MB limit fight).

**The lock**: all six tables (1 fact + 1 forecast mart + 4 dims) are Import.
No DirectQuery, no Dual, no composite, no UDA. Every visual interaction
runs against VertiPaq in-memory — sub-100ms for everything in the
dashboard.

**Free-tier confirmation**: Import storage mode + all built-in visuals +
full DAX (time intelligence, calculated columns, dynamic format strings) +
drill-through, bookmarks, sync slicers, field parameters are all free in
PBI Desktop with no Pro / PPU / Premium license. Verified against Microsoft
Learn.

---

## Semantic model

Six tables in the model at 5.9 close:

| Table                       | Source                | Rows         | Storage | Role                                                |
|-----------------------------|-----------------------|--------------|---------|-----------------------------------------------------|
| `FACT_DAILY_SALES`          | `WAREHOUSE`           | 32,959,690   | Import  | Single fact powering 5 of 5 pages                   |
| `MART_FORECAST_VS_ACTUAL`   | `MARTS`               | ~118,000     | Import  | Forecast layer powers Forecast vs Actual matrix     |
| `DIM_CALENDAR`              | `WAREHOUSE`           | 1,142        | Import  | Conformed date dimension (extended +60 days)        |
| `DIM_ITEM`                  | `WAREHOUSE`           | 3,049        | Import  | Item hierarchy (item → dept → cat)                  |
| `DIM_STORE`                 | `WAREHOUSE`           | 10           | Import  | Store + state                                       |
| `_Measures`                 | (no source)           | 0            | (n/a)   | Hidden table that homes all DAX measures            |

**`_Measures` is a discipline convention, not a data table.** Best practice
locked in `LEARNINGS.md` (2026-05-18). Right-click → "Enter data" → create
an empty table named `_Measures` with a single dummy column, hide the column,
then drag every DAX measure into `_Measures` via the Home tab Home table
dropdown on the Measure tools ribbon. Benefits: measures group together in
one place in the Data pane; right-click "Hide" on the dummy column hides
the table but keeps the calculator icon visible in the field list; future
maintenance is "where do I find that measure" = one place. Underscore prefix
sorts it to the top of the model alphabetically. Locked across every Phase 5
session.

**Autodetect-relationships disabled before loading** (CURRENT FILE setting).
Project #1 carry-forward — auto-detected relationships on first load
created clutter that had to be cleaned up; disabling at the model level
prevents it from happening.

**Auto-date/time also disabled** (GLOBAL + CURRENT FILE) — with a proper
`DIM_CALENDAR`, we don't want PBI auto-generating hidden date tables for
every Date column.

**Five relationships built manually** via drag-and-drop in Model View:

| From                                       | To                            | Cardinality   | Direction |
|--------------------------------------------|-------------------------------|---------------|-----------|
| `FACT_DAILY_SALES[date_key]`               | `DIM_CALENDAR[date_key]`      | Many-to-one   | Single    |
| `FACT_DAILY_SALES[item_key]`               | `DIM_ITEM[item_key]`          | Many-to-one   | Single    |
| `FACT_DAILY_SALES[store_key]`              | `DIM_STORE[store_key]`        | Many-to-one   | Single    |
| `MART_FORECAST_VS_ACTUAL[observation_date]`| `DIM_CALENDAR[calendar_date]` | Many-to-one   | Single    |
| `MART_FORECAST_VS_ACTUAL[item_id]`         | `DIM_ITEM[item_id]`           | Many-to-one   | Single    |

All single-direction filters. Filter propagation is fact → dims (and
mart → dims) only — no bidirectional cross-filter chains that could
silently poison a DAX measure.

The compute-same-way FK pattern from `LEARNINGS.md` makes these
relationships cheap: all surrogate keys are MD5 hashes of the same
natural-key inputs on both sides (fact + dim), so they match by
construction. Snowflake's optimiser resolves the joins as hash joins
with the small dims (1k-3k rows) held in memory. PBI's filter propagation
works the same way client-side after the Import load.

**`DIM_CALENDAR` extension — locked 2026-05-20 (session 5.4).**
`DIM_CALENDAR` extends 60 days past the max historical date in
`FACT_DAILY_SALES` to cover the forecast horizon on the Forecast vs Actual
page. At 5.9 close, fact max is 2014-03-25 and calendar max is 2014-05-24.
The `Active Items` measure references the fact's `sale_date` rather than
calendar's `calendar_date` to avoid the future-horizon empty-date trap
(if Active Items used calendar dates, the latest "today" would always be
60 days into the empty forecast horizon and return zero).

---

## Calculated columns + Power Query transformations

Three calculated columns on `DIM_CALENDAR`. All readability-driven — they
exist so visuals can render natural-language category labels (Weekday /
Weekend / SNAP Day / Non-SNAP Day) without per-visual DAX-IF gymnastics.

```dax
Day Type =
IF ( DIM_CALENDAR[IS_WEEKEND], "Weekend", "Weekday" )

SNAP Day Type =
IF (
    DIM_CALENDAR[SNAP_CA] = 1
        || DIM_CALENDAR[SNAP_TX] = 1
        || DIM_CALENDAR[SNAP_WI] = 1,
    "SNAP Day",
    "Non-SNAP Day"
)

is_snap_day =
IF (
    DIM_CALENDAR[SNAP_CA] = 1
        || DIM_CALENDAR[SNAP_TX] = 1
        || DIM_CALENDAR[SNAP_WI] = 1,
    TRUE,
    FALSE
)
```

`Day Type` powers the Weekday/Weekend X-axis on Seasonality & Calendar
(replacing the raw TRUE/FALSE boolean axis labels). `SNAP Day Type` powers
the donut Legend on Promotion & Price (replacing the raw boolean labels
with readable text). `is_snap_day` is the boolean version retained for
back-compatibility with measures that filter on it.

**Power Query transformation — single one in the model.** On
`MART_FORECAST_VS_ACTUAL.SERIES_TYPE`, the raw values from dbt are
lowercase `actual` and `forecast`. A single `Capitalize Each Word`
(`Text.Proper`) step in the Power Query Editor normalises to `Actual`
and `Forecast` so the matrix column headers read natively without
in-visual rename. Replaces two separate Replace Values steps from a
mid-session iteration (consolidated 2026-05-22). The transformation
sits at the lowest possible layer per the
`dbt → Power Query → DAX → visual` discipline hierarchy.

---

## The five pages

| # | Page                    | Source                              | Built in session |
|---|-------------------------|-------------------------------------|------------------|
| 1 | Executive Overview      | `FACT_DAILY_SALES`                  | 5.1, polished 5.7|
| 2 | Demand by Hierarchy     | `FACT_DAILY_SALES` + dims           | 5.6, polished 5.7|
| 3 | Promotion & Price       | `FACT_DAILY_SALES` + dims           | 5.6, polished 5.7|
| 4 | Seasonality & Calendar  | `FACT_DAILY_SALES` + `DIM_CALENDAR` | 5.6, polished 5.8|
| 5 | Forecast vs Actual      | `MART_FORECAST_VS_ACTUAL` (matrix)  | 5.6, polished 5.8|

All five pages source from `FACT_DAILY_SALES` via DAX measures on
`_Measures`, except the Forecast vs Actual matrix which sources from
`MART_FORECAST_VS_ACTUAL` because that's the only table carrying the
`series_type` discriminator column.

Cross-page Date + Category slicer sync established in session 5.7 (Date
slicer un-synced on Forecast vs Actual in 5.8 to enable the last-90-days
forecast horizon zoom while preserving the cross-page sync on the other 4
pages).

Theme: **City Park** built-in PBI theme applied uniformly. Design language
locked across pages: warm red as event / forecast / over-index callout
(Weekend, SNAP Day, Holiday bars, Forecast lines); grey as neutral baseline
(Weekday, Non-SNAP Day); green as sequential heat (heatmap gradient + Actual
line in Forecast charts); blue / purple / green as categorical coloring
keyed to `cat_id` (FOODS / HOBBIES / HOUSEHOLD).

---

## Page builds

### Page 1 — Executive Overview (session 5.1, polished 5.7)

Top-of-funnel landing page. Stakeholder opens the dashboard, this is what
they see first.

**Visuals**:

1. Title text box: *"Executive Overview"*
2. Date slicer on `DIM_CALENDAR[calendar_date]` — Between mode, compact
   two-date layout (no slider bar — slider was removed for space)
3. State slicer on `DIM_STORE[state_id]` — Tile mode, CA / TX / WI
4. Category slicer on `DIM_ITEM[cat_id]` — Tile mode, FOODS / HOBBIES /
   HOUSEHOLD
5. 4 KPI cards in a single compact row at top: **Revenue** (`$100.88M`),
   **Units Sold** (`37.04M`), **Stores** (`10`), **SKUs** (`3,049`)
6. Dual-axis line chart: **Revenue & Units** — `Total Revenue` (left axis)
   and `Total Units Sold` (right axis) over `calendar_date`, with
   `Revenue 30-Day MA` as a dashed black overlay

**Polish notes (5.7)**:

- City Park theme applied; KPI cards repositioned into one compact row
  with shortened labels (Revenue / Units Sold / Stores / SKUs) and renamed
  callout values
- Active Items card switched from `3K` to `3,049` via the new Card
  visual's Display units control: `Format → General → Data format → Whole
  number` (the control is buried under field-level "Apply settings to
  specific measure" in the Nov 2025 redesign — required a web-doc check
  mid-session to locate)
- `Total Revenue` set to `Format = Currency` at measure level (Measure
  tools ribbon) — propagates to every chart axis and tooltip using it,
  no per-visual axis formatting needed
- `Revenue 30-Day MA` added as the dashed-black overlay line, per-series
  color override via `Format → Visual → Lines → Colors`

**Why this is the cover page**: a stakeholder opening the dashboard sees
the headline numbers and the long-term shape of the business in one
glance, before deciding which deeper-cut page to navigate to.

### Page 2 — Demand by Hierarchy (session 5.6, polished 5.7)

Revenue cuts across the category → department → item hierarchy. Answers
"who's driving revenue, and what's the long-tail look like?"

**Visuals**:

1. Slicers: Date, State, Category (synced from Executive Overview)
2. **Revenue by Category** — clustered horizontal bar, Y = `cat_id`,
   X = `Total Revenue`, sort desc, data labels on
3. **Revenue by Department** — clustered horizontal bar, Y = `dept_id`,
   X = `Total Revenue`
4. **Category Hierarchy Breakdown** — matrix, rows = `cat_id` → `dept_id`
   → `item_id`, values = `Total Units Sold` + `Total Revenue` +
   `Revenue Share %`, default collapsed to `cat_id`
5. **Top 10 Items by Revenue** — table, columns = `item_id` + `cat_id` +
   `Total Revenue`, sorted desc, Top N filter = 10

**Polish notes (5.7)**:

- 2×2 grid layout with ~20px gaps (top row: 2 bar charts H=260 W=600;
  bottom row: matrix W=720 + table W=500 to fit the matrix's wider
  `%GT Revenue Share` column)
- Category-keyed bar colors via `Color → fx → Format style Rules`, basing
  on `cat_id` with operator `contains` and 3 rules: FOODS → dark blue,
  HOUSEHOLD → green, HOBBIES → purple
- Matrix `%GT Revenue Share` column header prefix stripped via right-click
  on field in Values well → `Show value as` → `No calculation`
- All 4 visual titles renamed: Revenue by Category / Revenue by Department
  / Category Hierarchy Breakdown / Top 10 Items by Revenue

**Insight surfaced**: FOODS dominates revenue at ~$60M (59% of total);
HOUSEHOLD at $30M (29%); HOBBIES at $11M (11%). Top 10 SKUs concentrate
only ~5.7% of total revenue ($5.74M of $100.70M) — classic retail
long-tail distribution.

### Page 3 — Promotion & Price (session 5.6, polished 5.7)

Price elasticity and SNAP-benefit-day story. Answers "what's the price
shape, and how much of our revenue depends on SNAP days?"

**Visuals**:

1. Slicers: Date, State, Category (synced)
2. **Average Selling Price** — clustered column chart, X = `cat_id`,
   Y = `Avg Selling Price`
3. **Revenue: SNAP vs Non-SNAP Days** — donut chart, Legend =
   `SNAP Day Type`, Values = `Total Revenue`
4. **Price vs Revenue by Department** — scatter, X = `Avg Selling Price`,
   Y = `Total Revenue`, Legend = `cat_id`, Details = `dept_id`,
   Size = `Total Revenue`

**Polish notes (5.7)**:

- Avg Selling Price column chart category-colored via `Format → Visual →
  Columns` (not Bars — vertical column charts use the Columns section in
  the new format pane) → Color → fx → same Rules pattern as page 2
- Y-axis switched to currency `$0.00 / $2.00 / $4.00 / $6.00` via
  measure-level `Format = Currency` on `Avg Selling Price`
- Donut retitled "Revenue: SNAP vs Non-SNAP Days"; Detail labels →
  `Label contents = Category, percent of total`, Position = Outside;
  warm red for SNAP Day (callout) and grey for Non-SNAP Day (baseline)
- Scatter retitled "Price vs Revenue by Department"; bubble Size bound
  to `Total Revenue`; per-series marker colors set via `Format → Visual
  → Markers → Apply settings to dropdown` → pick FOODS/HOBBIES/HOUSEHOLD
  individually; custom marker shapes per category (triangle/diamond/circle)
- X-axis padded Start=2 End=6.5 to stop dots clipping at edges

**Insight surfaced**: SNAP days drive ~52% of revenue from only ~33% of
calendar days — strong correlation between SNAP benefit distribution and
shopping behaviour. FOODS_3 surfaces in the scatter as the cheap-price /
high-volume outlier (~$2.80 avg / $40M revenue) — classic price-elasticity
in one visual.

### Page 4 — Seasonality & Calendar (session 5.6, polished 5.8)

Calendar effects on demand. Answers "when do people shop, and which days
of the year matter most?"

**Visuals**:

1. Slicers: Date, State, Category (synced)
2. **Revenue: Weekday vs Weekend** — column chart, X = `Day Type`,
   Y = `Total Revenue`, Weekend in warm red callout color, Weekday in
   grey baseline, Y-axis off, data labels carry the story
3. **Revenue Impact by Holiday Event** — bar chart, Y = `event_name_1`,
   X = `Holiday Revenue`, Top N = 10 filter via Filter pane, X-axis off,
   $-formatted data labels via measure-level Format = Currency
4. **Monthly Revenue by Year** — matrix, rows = `YEAR`, columns =
   `MONTH_NAME` (sorted by `MONTH` via Sort by Column), values =
   `Total Revenue`

**Polish notes (5.8)**:

- `Day Type` calc column added to `DIM_CALENDAR` so the Weekday/Weekend
  bar chart axis renders readable text labels rather than raw TRUE/FALSE
- `SNAP Day Type` calc column (text) rewritten in place from the original
  `is_snap_day` boolean — eliminates the intermediate boolean → text step
  for the page 3 donut Legend
- All 3 visual titles renamed
- Heatmap matrix: green single-color sequential gradient via `Cell
  elements → fx → Format style Gradient`; "How should we format empty
  values?" set to `Don't format` killing the 2014 partial-year red
  distortion; `Apply to = Values only` excluding the Total column/row
  from the gradient; Grow to fit via `Layout → Column width →
  Auto-size behavior` + `Custom widths Off`; Row padding bumped to 10
  in `Grid → Options`; Global font size 11
- Matrix gridlines width set to 0 to fill solidly

**Insight surfaced**: Weekend revenue over-indexes ~33% per day
(weekend $17.5M/day vs weekday $13.2M/day). SuperBowl is the strongest
single-day holiday uplift at $0.43M. Year-on-year growth across the
heatmap is the cleanest takeaway — 2011 $23.9M, 2012 $32.6M, 2013 $35.9M
(~50% growth across the history).

### Page 5 — Forecast vs Actual (session 5.6, polished 5.8)

Where the project's ML layer (Snowflake Cortex forecast) lands in the
dashboard. Answers "how is the forecast tracking, and what does the next
30 days look like?"

**Visuals**:

1. Slicers: Date (un-synced from cross-page sync to enable last-90-days
   zoom) + Category. No State slicer — forecast was trained at item-level
   grain, no State path in the mart
2. **Forecast Revenue** KPI card (`$2.89M`) top-right
3. **Forecast Units** KPI card (`1.02M`) top-right, duplicated from
   Forecast Revenue
4. **Revenue: Actual vs Forecast** — line chart, X = `observation_date`,
   Y = `Actual Revenue` (solid green) + `Forecast Revenue` (dashed red)
5. **Units: Actual vs Forecast** — line chart, X = `observation_date`,
   Y = `Actual Units` (solid green) + `Forecast Units` (dashed red) +
   `Forecast Upper 95` (dotted dark blue) + `Forecast Lower 95`
   (dotted pale grey)
6. **Actual vs Forecast by Category** — matrix, rows = `cat_id`,
   columns = `series_type` (Actual / Forecast / Total),
   values = `Total Units (Mart)` + `Total Revenue (Mart)`

**Polish notes (5.8)**:

- Per-series styling via `Format → Visual → Lines → Apply settings to`:
  Actual = solid green; Forecast = dashed warm red; Upper 95 = dotted
  dark blue; Lower 95 = dotted pale grey
- Date slicer un-synced via `View → Sync slicers panel` (uncheck Sync
  for Forecast vs Actual row, keep Visible) — zoom to last 90 days
  (1/01/2014 → 24/05/2014) shows forecast horizon clearly without
  affecting other 4 pages' synced Date selections
- Matrix `SERIES_TYPE` values normalised via Power Query
  `Text.Proper` → Actual / Forecast (one step, not the original two
  Replace Values)
- Matrix measure column headers renamed via right-click `Rename for
  this visual` to drop `(Mart)` suffix (`Total Units (Mart)` → Units,
  `Total Revenue (Mart)` → Revenue) while keeping the (Mart) suffix on
  the underlying measures in `_Measures` for documentation
- Matrix `Layout → Column width → Custom widths Off`;
  `Grid → Options Row padding 10 / Global font size 11`;
  alternate background color set to `No fill` killing the row banding

**Critical architectural note — why the matrix needs mart-sourced
measures.** The `Total Units Sold` / `Total Revenue` fact-sourced
measures from §2.1 of the playbook cannot drive the
`series_type`-split matrix, because `FACT_DAILY_SALES` has no
`series_type` column. There's no path from `MART_FORECAST_VS_ACTUAL.
series_type` to `FACT_DAILY_SALES`, so both columns of the matrix would
render the same total. Solution: a second pair of mart-sourced measures
(`Total Units (Mart)`, `Total Revenue (Mart)`) that aggregate
`MART_FORECAST_VS_ACTUAL` directly — these CAN be filtered by
`series_type` because the column lives on the same table. Naming
convention: same metric name + `(Mart)` suffix, side-by-side in the
field list. Pattern carries forward to any future "actual vs forecast"
or "current vs prior" mart scenario.

---

## DAX measure library — 16 measures

All measures live on the hidden `_Measures` table. Source table is
`FACT_DAILY_SALES` unless the measure name ends in `(Mart)` (these
source from `MART_FORECAST_VS_ACTUAL`).

### Base measures (4)

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

`Total Revenue` formatted as Currency at measure level — propagates to
every visual using it (axis labels, data labels, tooltips). `Total Units
Sold` formatted as `#,0`. Counts formatted as whole numbers.

**`Active Items` semantic — LOCKED 2026-05-19.** Returns distinct items
selling AS AT the latest date in the current filter context. Answers
"how many SKUs are active right now?" — most intuitive read for an exec
KPI card.

### Page-specific measures (3)

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

Holiday Revenue =
CALCULATE ( [Total Revenue], DIM_CALENDAR[is_holiday] = TRUE )
```

`Revenue Share %` formatted as Percentage. `Avg Selling Price` formatted
as Currency. `Holiday Revenue` formatted as Currency.

### Forecast measures (8 — source `MART_FORECAST_VS_ACTUAL`)

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

`Forecast Revenue` / `Actual Revenue` / `Total Revenue (Mart)` formatted
as Currency. Units measures formatted as `#,0`.

### Time intelligence (1)

```dax
Revenue 30-Day MA =
AVERAGEX (
    DATESINPERIOD (
        DIM_CALENDAR[calendar_date],
        MAX ( DIM_CALENDAR[calendar_date] ),
        -30,
        DAY
    ),
    [Total Revenue]
)
```

Prerequisite: `DIM_CALENDAR` marked as Date Table on `calendar_date`
(`Table tools → Mark as date table`). Auto Date/Time stays disabled.

**Four time-intel measures deleted at 5.8 close** (Revenue PY / Revenue
YoY $ / Revenue YoY % / Revenue YTD). Built for YoY indicator + YTD pill
patterns that were skipped due to the new Card visual's Reference labels
field well missing in this PBI Desktop variant. DAX retained in
`POWERBI_PLAYBOOK.md` §2.5 for reference / future recreation.

### Deleted measures retained in playbook for reference

- `SNAP Day Revenue` (deleted 2026-05-21) — superseded by `is_snap_day`
  calc column + `Total Revenue` donut build pattern
- `Weekend Revenue %` (deleted 2026-05-21) — superseded by `IS_WEEKEND`
  axis + `Total Revenue` bar chart
- 4 unused time-intel measures (deleted 2026-05-22) — see above

---

## Cross-page UX

### Sync slicers

Date + Category slicers synced across all 5 pages via `View → Sync
slicers panel`. State slicer synced across the 4 fact-driven pages
(omitted on Forecast vs Actual by design — no State path in the forecast
mart).

**Date slicer un-synced on Forecast vs Actual** (5.8). Allows the
Forecast vs Actual page to zoom to last-90-days
(1/01/2014 → 24/05/2014) showing the forecast horizon clearly, without
affecting the other 4 pages' synced Date selections. Per-page slicer
sync behavior is the Sync slicers panel's two-checkbox column: Sync ON
+ Visible ON = synced and visible; Sync OFF + Visible ON = independent
local slicer (the Forecast vs Actual pattern).

### Theme

City Park built-in PBI theme applied (`View → Themes → City Park`).
Tested across all 5 pages — didn't snap any of the manually-colored
visuals back to default blues.

Design language locked across pages:

- **Warm red** as event / forecast / over-index callout (Weekend bar,
  SNAP Day donut slice, Holiday bars, Forecast line series)
- **Grey** as neutral baseline (Weekday bar, Non-SNAP Day donut slice)
- **Green** as sequential heat / actual data (heatmap gradient, Actual
  line series in Forecast charts)
- **Blue / purple / green** as categorical, keyed to `cat_id` (FOODS dark
  blue, HOBBIES purple, HOUSEHOLD green)

### Drill-through — ATTEMPTED and PULLED (5.8)

Item Detail destination page built per spec: Card showing `item_id`,
Table with `calendar_date` / `store_id` / `state_id` / `Total Units Sold`
/ `Total Revenue`, drill-through field well wired with `DIM_ITEM[ITEM_ID]`
+ `Allow drill through when = Used as category` + `Keep all filters Off`,
page hidden.

**Right-click trigger did not fire** from source visuals (tested on Top
10 Items table on Demand by Hierarchy). Context menu showed standard
Copy / Show as table / Include / Exclude items, but no "Drill through"
option. Diagnostics tried: save + close + reopen, lineage tooltip
confirmation (`DIM_ITEM[ITEM_ID]` in both source and destination), Page
type dropdown check (`Drillthrough` toggle not exposed in this stock-free
PBI Desktop variant — Page information section only shows `Set as
landing page` / `Allow use as tooltip` / `Allow Q&A`).

Community-cited fix (set Page type = Drillthrough) didn't apply because
the toggle doesn't exist in this variant. **Decision**: pull rather than
chase a variant-specific UI issue. Item Detail page deleted. PBI's
automatic cross-filtering carries the page-level interactivity story
without drill-through.

LEARNING locked: pick theme + test drill-through EARLY in the build, not
at polish time — if drill-through silently fails, you want to know
before three pages of careful formatting depend on a future drill action
that won't fire.

---

## Performance — VertiPaq Analyzer results

Exported via DAX Studio at 5.8 close: `powerbi/retail_demand_forecasting.vpax`
(76 KB). Captures per-column cardinality, dictionary size, encoding type,
and table sizes at session-close model state.

| Metric                              | Value           |
|-------------------------------------|-----------------|
| Total compressed model size         | ~254 MB         |
| `FACT_DAILY_SALES` share            | ~67% (~170 MB)  |
| Forecast layer share                | ~25% (~65 MB)   |
| Dims + measures + headers           | ~8% (~19 MB)    |
| Avg columnar compression            | ~5 bytes/row/col|
| `FACT_DAILY_SALES` row count        | 32,959,690      |

VertiPaq's columnar compression on the trimmed fact + 60-day forecast
horizon brings the on-disk model into manageable size for the repo
(committed via Git LFS). All five pages run sub-100ms against the
in-memory model — every slicer click, every page navigation, every
filter change.

**DAX Studio install gotcha (5.8)**: per-user install of DAX Studio
("Install for me only") places `daxstudio.pbitool.json` in
`%LOCALAPPDATA%\DAX Studio\` rather than the all-users path PBI Desktop
scans (`C:\Program Files (x86)\Common Files\Microsoft Shared\Power BI
Desktop\External Tools\`). External Tools ribbon tab does not appear.
Workaround: launch DAX Studio standalone via Start Menu, connect via
the Connect dialog's `Power BI / SSDT Model` radio button. Permanent
fix is reinstall as "Install for all users" — TBD next install.

---

## Polish discipline rules — 13+ LEARNINGS from the PBI build

Operational rules captured across sessions 5.1-5.9. The full text of each
lives in `LEARNINGS.md`; the summary below is the cheat-sheet for Phase 6
and Project #3 carry-forward.

### Diagnostic-order rules

1. **Optimize → Pause Visuals is the FIRST diagnostic** when symptoms
   include "things blank on click" / "needs refresh after every change" /
   "slicer empty even though data exists". 1-click toggle on the Optimize
   ribbon, highest-signal PBI diagnostic. The icon shown is the action
   that would happen on click, not the current state — counterintuitive.
   Pause Visuals can surface a spurious cyclic-reference error too — if
   the cyclic ref appears alongside other "everything is broken"
   symptoms, check Pause Visuals before tracing the model.
2. **Cyclic reference errors — two causes, two diagnostic orders.**
   (a) Spurious cache desync → save + close + reopen clears instantly.
   (b) Real Power Query M-code self-reference → open PQ Editor, inspect
   each Applied Step's first argument, must be `#"PreviousStep"` not the
   query name itself. Try (a) first because it's cheaper.
3. **When 3 things look broken at once, suspect ONE root cause** and try
   the cheapest single-variable fix first. Multiple symptoms appearing
   together usually means one upstream cause, not three independent
   bugs. Real example from 5.5: empty slicers + broken KPI cards +
   refresh-time cyclic ref were all downstream of Pause Visuals being
   on. One click fixed all three.

### Architecture-discipline rules

4. **Measures live on `_Measures` only. Never on data tables.** Right-
   click → New measure → Home table dropdown → `_Measures`. Hidden
   dummy column. Searchable, organised, future-proof.
5. **Measures aggregate `FACT_DAILY_SALES` or `MART_FORECAST_VS_ACTUAL`
   only.** Never aggregate aggregate tables — if you build an agg
   pattern in the future, UDA routes for you transparently.
6. **Everything Import.** No DirectQuery, no Dual, no composite. If a
   recommendation requires non-Import storage mode, push back. Locked
   2026-05-20 after the UDA detour.
7. **When dragging a field into a visual, use the named measure from
   `_Measures`, never a raw column.** Implicit `Sum of <column>`
   aggregations are a red flag — they bypass the explicit-measure layer
   and break the formula → visual lineage.
8. **`(Mart)` measure naming pattern** for forecast-aware models. When
   the same metric lives on two source tables (fact-sourced and
   mart-sourced), suffix the mart-sourced version `(Mart)` rather than
   renaming the original. Self-documenting; field list shows them
   side-by-side alphabetically.
9. **Transformation layer hierarchy: dbt → Power Query → DAX → visual.**
   Do data cleanup at the lowest layer possible. Categorical text
   normalisation that lives in dbt is portable, testable, and visible
   to all consumers; cleanup in PBI is invisible to anyone reading the
   dbt models. The single PQ `Text.Proper` step in this model is the
   exception that proves the rule — it normalises a column for PBI
   only because the dbt source needs the lowercase value for its own
   use.

### UI / format-pane rules

10. **PBI format pane control locations vary heavily by variant.** Pin
    EXACT paths from a screenshot before prescribing. Documented
    locations:
    - Matrix Row padding: `Grid → Options` (not `Row headers`)
    - Matrix Grow to fit: `Layout → Column width` + Custom widths Off
    - Conditional formatting: `Cell elements → Apply settings to → fx`
    - New Card visual Value field: `Value` field well (not `Fields`)
    - Display units on new Card: buried under field-level "Apply
      settings to specific measure"
    - Bars / Columns / Markers / Slices — different format pane section
      names depending on visual type
11. **Basic-license PBI Desktop variants may be missing optional new-
    visual features.** Feature-detect on a screenshot before
    recommending. Known gaps in this variant: new Card visual Reference
    labels field well (blocks YoY indicator pattern); Page type =
    Drillthrough toggle (blocks drill-through).
12. **Snowflake unquoted identifiers → UPPERCASE in PBI catalog.** dbt
    lowercase → Snowflake uppercase → PBI uppercase. DAX is case-
    insensitive for references, but trust Intellisense rather than
    free-typing lowercase versions.
13. **Calculated COLUMN vs MEASURE** — same formula bar, different
    evaluation context. The "Cannot find name [column]" error on a
    column you can see in the Data pane is the canonical symptom of
    clicking New measure when you wanted New column. Always check the
    ribbon button FIRST before debugging the formula.
14. **Measure formula commits require an explicit green-checkmark click**
    when EDITING. Enter does not commit — it inserts a newline. Pure
    NEW measure save can use Enter.
15. **Measure-level `Format = Currency`** (Measure tools ribbon)
    propagates everywhere the measure is used. Set once, applies to
    every axis, every data label, every tooltip.

### Build-order rules

16. **PBI build order — theme + drill-through test EARLY, not at polish
    time.** Theme propagation reorganises formatted visuals; failed
    drill-through trigger fix often requires delete + re-add of source
    visual. Test the pattern with 1-2 visuals before investing in
    page-wide formatting.
17. **Pacing — 1-2 steps per response on UI walkthroughs, 3-4 absolute
    max.** Phil's preference for any new tool. Stop and wait for
    confirmation or screenshot between steps.

### Data-correctness rules

18. **`DIM_CALENDAR` extends 60 days past the max historical date.**
    Powers the forecast horizon on Forecast vs Actual. `Active Items`
    measure uses the fact's `sale_date` not calendar's `calendar_date`
    to avoid the future-horizon empty-date trap.
19. **Power Query Replace Values is the only stock-Desktop path for
    renaming categorical column values.** In-visual rename works only
    for measure pills, not category values driving column headers. The
    `Text.Proper` step in this model collapses to one PQ step rather
    than two Replace Values steps.

---

## What Phase 6 captured but didn't change

Phase 6 is documentation + ship — README screenshots of the 5 pages, this
walkthrough fill-in, future-revival paragraph, final commit + v1.0 tag.
No model changes, no measure changes, no page-build changes from the 5.8
close state.

End-of-Phase-5 model snapshot (also the v1.0 release snapshot):

- 6 tables in the semantic model (1 fact + 1 forecast mart + 4 dims +
  `_Measures` hidden)
- 16 measures + 3 calculated columns on `DIM_CALENDAR`
- 1 Power Query transformation (`Text.Proper` on
  `MART_FORECAST_VS_ACTUAL.SERIES_TYPE`)
- 5 polished pages, City Park theme, design language locked
- ~254 MB compressed VertiPaq model, sub-100ms interaction latency
- All-Import storage mode

---

## Future revival for interview demo

`.pbix` is Import-mode — opening the file demos the entire dashboard
standalone, no Snowflake connection required. Data is baked into the
VertiPaq cache at the session-close save. Portfolio reviewers (recruiter,
hiring manager) get the full BI deliverable by opening the file in PBI
Desktop.

If a **live refresh demo** is needed for an interview 30+ days out (after
the Snowflake free trial credits expire), the revival path is:

1. Top up Snowflake with pay-as-you-go on the Standard tier the week
   before the interview (~$5 expected spend for a week of light demo
   refreshes against a small XSMALL warehouse)
2. Open `.pbix` → Home → Refresh → re-authenticate to Snowflake when
   prompted → data pulls live from `WAREHOUSE` + `MARTS`
3. Demo end-to-end pipeline: trigger `m5_daily_extract` for a fresh
   logical_date in Airflow, watch the 4 tasks go green, refresh PBI,
   show the new row in `FACT_DAILY_SALES` Data view (sort `SALE_DATE`
   descending → top row is the just-extracted date)

Cost ceiling for the demo week is bounded — XSMALL warehouse + 60s
auto-suspend + cold-start cost ~$0.0003 per 60-second window of activity.
A demo session running 4-5 PBI refreshes + 2-3 Airflow DAG triggers
across an hour is well under $1; the $5 budget is comfortable headroom.

Future-Phil reading this in 2-3 years: the .pbix opens standalone, the
agg marts + forecast model + Airflow DAG + dbt project are all on the
public repo, the architectural decisions are documented in this file +
`EXTRACT_PIPELINE.md` + `DBT_PIPELINE.md`. Reviving the live demo is a
week of pay-as-you-go + reconnecting credentials, no rebuild needed.

---

## Cross-references

- `POWERBI_PLAYBOOK.md` — locked source of truth for the build (specs,
  measure definitions, page-by-page plan, clean rebuild checklist)
- `LEARNINGS.md` → Power BI section — full text of every LEARNING
  summarised in §13 above
- `EXTRACT_PIPELINE.md` — Azure SQL → Snowflake `RAW` extract layer
- `DBT_PIPELINE.md` — `RAW` → `STAGING` → `INTERMEDIATE` → `WAREHOUSE`
  → `MARTS` transformation layer
- `PROJECT_CONTEXT.md` — session-by-session closeout history
- `sql/snowflake/04_grant_powerbi_reader.sql` — least-privilege role
  provisioning
- `sql/snowflake/05_train_forecast_model.sql` — Snowflake Cortex ML
  forecast model training
- `dbt/models/marts/mart_forecast_vs_actual.sql` — forecast layer mart
  that powers page 5
