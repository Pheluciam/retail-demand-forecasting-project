# POWERBI_PIPELINE.md — Power BI Dashboard Walkthrough

> Companion to `EXTRACT_PIPELINE.md` and `DBT_PIPELINE.md`. This doc explains
> the Power BI layer that consumes the dbt-built `WAREHOUSE` star schema to
> surface a five-page analyst-facing dashboard.
>
> Last updated: 2026-05-20 (Phase 5 session 5.4 close).
>
> **Architectural note — read first.** This doc was initially scaffolded in
> Phase 5 session 5.1 against a `lean-marts + DirectQuery on the fact` model
> that is no longer current. The architecture was rewritten in session 5.3
> (deep-research audit) to **all-Import + user-defined aggregations + a
> Snowflake Cortex ML forecast layer**, and the UDA portion was further
> refined in session 5.4 after Microsoft Learn confirmed UDA requires a
> DirectQuery detail table (architecturally incompatible with all-Import).
> The locked source of truth for the PBI build is `POWERBI_PLAYBOOK.md`,
> revised 2026-05-19 and patched 2026-05-20 at close of session 5.4.
> Sections below that reference `mart_executive_overview`, the lean-marts
> pattern, or DirectQuery storage mode are historical context for sessions
> 5.1-5.2 and are scheduled for rewrite in session 5.6 polish.

---

## What Power BI does in this project

Power BI is the consumption layer that closes the end-to-end story: Azure SQL →
Snowflake RAW → dbt-built `STAGING` / `INTERMEDIATE` / `WAREHOUSE` / `MARTS` →
**Power BI Desktop dashboard**. The pipeline produces an analytical model in
Snowflake; Power BI turns it into a five-page business-facing dashboard that
operations / S&OP stakeholders can use to answer demand-planning questions.

**Key mental model.** Power BI is the *retail clerk on a tour* of the Snowflake
warehouse. It walks in with a read-only badge (`POWERBI_READER`), reads the
shelves it's allowed to see (`WAREHOUSE.fact_*` + `dim_*` + `MARTS.mart_*`),
and renders what it sees into visuals. It never builds, restocks, or moves
anything — all that happens upstream in dbt. Pretty labels, derived columns,
and business-logic transformations live in dbt, not DAX.

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
RETAIL_DB.MARTS        ← dbt marts — pre-aggregations (Phase 4)
        ↓
Power BI Desktop       ← THIS DOC (Phase 5)
        ↓
Five-page dashboard    ← Phase 5 sessions 5.1 – 5.6
```

Power BI connects to Snowflake via the **native Snowflake connector** under
the dedicated **`POWERBI_READER`** role (least-privilege; see
`sql/snowflake/04_grant_powerbi_reader.sql`). The semantic model follows the
**lean-marts pattern** locked in `LEARNINGS.md` (2026-05-17): the four
sliceable pages consume the warehouse star directly (`fact_daily_sales` +
`dim_item` + `dim_store` + `dim_calendar`); the Home page consumes the
pre-aggregated `mart_executive_overview` for instant refresh.

---

## The five pages

| # | Page | Source | Session |
|---|---|---|---|
| 1 | Executive Overview (Home) | `MARTS.mart_executive_overview` | 5.1 |
| 2 | Demand by Hierarchy | `WAREHOUSE.fact_daily_sales` + dims | 5.2 |
| 3 | Promotion & Price | `WAREHOUSE.fact_daily_sales` + dims | 5.2 |
| 4 | Seasonality & Calendar | `WAREHOUSE.fact_daily_sales` + `dim_calendar` | 5.3 |
| 5 | Forecast vs Actual | `MARTS.mart_forecast_vs_actual` (built session 5.4) | 5.5 |

Cross-page sync slicers, drill-throughs, theme polish, and VertiPaq
performance tuning land in session 5.6 as the closing pass.

---

## Snowflake connection (Phase 5 session 1)

Power BI Desktop connects to Snowflake via the **native Snowflake connector** (`Get Data → More → Snowflake`). Three fields configure the connection:

- **Server**: `<account_locator>.<region>.snowflakecomputing.com`. For this project: `tq94402.ap-southeast-2.snowflakecomputing.com` (AWS Sydney region, surfaced via `SELECT CURRENT_ACCOUNT(), CURRENT_REGION();` in Snowsight).
- **Warehouse**: `WH_RETAIL` — the XSMALL compute warehouse provisioned in Phase 2. Auto-resumes on connection, auto-suspends after 60s idle.
- **Advanced Options → Role name**: `POWERBI_READER` — pins the session to the least-privilege read-only role at the connection level. Critical: without this, PBI falls back to the user's default role (`RETAIL_ENGINEER` for our user PHELUCIAM), which has full ownership of WAREHOUSE + MARTS schemas. Pinning the role makes the principle-of-least-privilege story enforceable.

**`POWERBI_READER` role** is provisioned by `sql/snowflake/04_grant_powerbi_reader.sql`. It grants:

- `USAGE` on `WH_RETAIL` (run queries, no OPERATE)
- `USAGE` on `DATABASE RETAIL_DB` (see in metadata, no CREATE SCHEMA)
- `USAGE` + `SELECT` (existing + future tables/views) on `RETAIL_DB.WAREHOUSE` and `RETAIL_DB.MARTS`
- Explicitly NO grants on `RAW` / `STAGING` / `INTERMEDIATE` — Power BI never sees the kitchen prep

Granted to user PHELUCIAM as a second role alongside `RETAIL_ENGINEER` (reuse-existing-user pattern; service-account separation deferred to Project #3 if needed). The connection string's role pin scopes PBI's queries to read-only even though the underlying user can switch roles in Snowsight.

**Verification**: `SHOW GRANTS TO ROLE POWERBI_READER` returns only `USAGE` + `SELECT` rows — no `INSERT/UPDATE/DELETE/TRUNCATE/CREATE`. Negative test (commented-out at the bottom of the SQL file) — `SELECT COUNT(*) FROM RETAIL_DB.RAW.M5_SALES_TRAIN` under POWERBI_READER returns **"Object does not exist or not authorized"** — the boundary genuinely bites.

**One real gotcha hit**: PBI's Navigator initially showed all 7 schemas in RETAIL_DB (including RAW/STAGING/INTERMEDIATE) under POWERBI_READER. Looked like a privilege leak. Diagnosed via `INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER('PHELUCIAM')` — confirmed every PBI metadata query ran under POWERBI_READER. The schema listing is Snowflake's standard metadata behavior (`SHOW SCHEMAS IN DATABASE` returns all schemas in a database the role has DB-level USAGE on, regardless of per-schema privileges). USAGE on the schema controls whether you can OPEN it; metadata visibility is broader. See `LEARNINGS.md` → "2026-05-18 — Snowflake metadata visibility ≠ access boundary" for the visitor-badge analogy.

**Another real gotcha hit**: first re-connect attempt after editing data source settings failed with `ODBC: 260002 Password is empty`. Root cause: PBI saves credentials per-server separately from connection settings; editing one without re-entering the other desyncs them. Fix: `File → Options → Data source settings → Clear Permissions + Delete → reconnect from scratch with auth re-entered`.

---

## DirectQuery vs Import — empirical per-page evaluation

**Decision principle**: evaluate per page, not per project. Different visuals have different size and freshness requirements; the right mode varies.

**Session 5.1 — Home page (`mart_executive_overview`): Import** decisively. Reasoning:

| Factor | Why Import wins for the mart |
|---|---|
| Size | 1,081 rows × 6 columns. VertiPaq compresses this to a few KB. Sub-millisecond render. |
| Refresh cadence | Mart only updates when dbt builds run (~daily). No need for live queries. |
| DAX surface | Import unlocks full DAX — time intelligence (YTD/QTD/MTD), calculated columns, calculated tables. DirectQuery restricts many of these. |
| Cost | Import = one Snowflake query per refresh. DirectQuery = one query per visual interaction. For 1,081 rows, Import is dramatically cheaper. |

**Spreadsheet analogy**: Import is *downloading the spreadsheet to your laptop and working offline* — fast, full feature set, refresh manually. DirectQuery is *editing the spreadsheet on a shared server over the network* — always fresh, but every click is a round-trip. For a tiny daily-refreshed mart, the laptop copy is overwhelmingly correct.

**Session 5.1 — Warehouse star (`FACT_DAILY_SALES` + 3 dims): empirical pivot to composite mode.** Initial decision was full Import after observing the 32.9M-row fact loaded over residential internet in ~10 minutes into VertiPaq. **The actual constraint we hit at git-push time**: the resulting `.pbix` was **949 MB** — VertiPaq compressed the row data fine, but the model file still exceeded GitHub's **100 MB per-file push limit**. Pivoted to **composite mode** at session close: **DirectQuery** on `FACT_DAILY_SALES` (32.9M rows stay in Snowflake, queries fire on demand for fact-driven visuals); **Import** on `MART_EXECUTIVE_OVERVIEW` + 3 dims (small tables, instant interactivity for home page + cached dim attributes). Result: `.pbix` dropped to **264 KB** (a ~3,600× reduction), pushes cleanly without LFS, no GitHub bandwidth quota concerns, and ships a senior-DE composite-mode pattern as the real interview talk-track.

**Mechanics of the pivot**: PBI Desktop **cannot change a table's storage mode from Import to DirectQuery via the Properties pane dropdown** (the option is greyed out by design — Import → Import-or-Dual is allowed, Import → DirectQuery is not, because Import mode unlocks features that DirectQuery doesn't support). The correct path is: **delete the table from the model**, then **re-add via Get Data and choose DirectQuery at the load dialog**. Relationships are lost on delete and must be rebuilt afterward. Web-confirmed; documented in `LEARNINGS.md` → "2026-05-18 — .pbix file size forced composite-mode decision".

**Session 5.2+ measurement**: the new slicing pages will fire DirectQuery calls against the 32.9M fact for every visual interaction. Measure first-render latency and per-click responsiveness; if any page chokes, the fallback is **PBI Aggregations** — user-defined Import-mode aggregation tables that PBI auto-routes queries to when grain permits, falling back to DirectQuery for detail. Best-of-both-worlds, more complex to configure.

---

## Semantic model

Built under the lean-marts pattern (`LEARNINGS.md` → "2026-05-17 — Lean marts layer + analyst-facing star schema"). Five tables in the model:

| Table | Source | Rows | Storage Mode | Role |
|---|---|---|---|---|
| `MART_EXECUTIVE_OVERVIEW` | `RETAIL_DB.MARTS` | 1,081 | Import | Powers the Executive Overview page |
| `FACT_DAILY_SALES` | `RETAIL_DB.WAREHOUSE` | 32,959,690 | **DirectQuery** | Powers sliceable pages 5.2–5.4 |
| `DIM_CALENDAR` | `RETAIL_DB.WAREHOUSE` | 1,082 | Import | Conformed date dimension |
| `DIM_ITEM` | `RETAIL_DB.WAREHOUSE` | 3,049 | Import | Item hierarchy (item/dept/cat) |
| `DIM_STORE` | `RETAIL_DB.WAREHOUSE` | 10 | Import | Store + state |

**Autodetect-relationships disabled before loading** (CURRENT FILE setting). Project #1 carry-forward — auto-detected relationships on first load created clutter that had to be cleaned up; disabling at the model level prevents it from happening. **Auto-date/time also disabled** (GLOBAL + CURRENT FILE) — with a proper `dim_calendar`, we don't want PBI auto-generating hidden date tables for every Date column.

**Four relationships built manually** via drag-and-drop in Model View:

| From | To | Cardinality | Direction |
|---|---|---|---|
| `FACT_DAILY_SALES.date_key` | `DIM_CALENDAR.date_key` | Many-to-one | Single |
| `FACT_DAILY_SALES.item_key` | `DIM_ITEM.item_key` | Many-to-one | Single |
| `FACT_DAILY_SALES.store_key` | `DIM_STORE.store_key` | Many-to-one | Single |
| `MART_EXECUTIVE_OVERVIEW.sale_date` | `DIM_CALENDAR.calendar_date` | Many-to-one (overridden from 1:1) | Single |

The MART→DIM_CALENDAR override deserves its own note: PBI auto-detected it as **One to one (1:1)** because both columns are unique. PBI then **locked cross-filter direction to "Both"** — no Single option for 1:1. Bidirectional from mart→calendar would have leaked filters across to fact via calendar — exactly the hidden cross-filter chain that produces wrong DAX later. Fix: manually override cardinality to Many-to-one (PBI shows a benign data-integrity warning, accept it). Single direction filter unlocks. Star-schema purity > technical accuracy. See `LEARNINGS.md` → "2026-05-18 — Mart→calendar 1:1 cardinality override" for the full reasoning.

The compute-same-way FK pattern from `LEARNINGS.md` makes these relationships cheap: all surrogate keys are MD5 hashes of the same natural-key inputs on both sides (fact + dim), so they match by construction. Snowflake's optimiser resolves the joins as hash joins with the small dims (1k–3k rows) held in memory. PBI's filter propagation works the same way client-side after the Import load.

---

## Page builds

### Executive Overview (Phase 5 session 1)

Sources from `MART_EXECUTIVE_OVERVIEW` (1,081 daily summary rows pre-aggregated by dbt from 32.9M fact rows — ~30,500× compression). Built with five visuals:

1. **Title** — text box at the top: *"Executive Overview — Retail Demand Dashboard"*
2. **Date range slicer** on `DIM_CALENDAR[calendar_date]`. Defaulted to "Between" mode (slider with two handles, date range pickers on both sides). Covers full 1,082-date span.
3. **KPI Card: Total Revenue** — `Total Revenue = SUM(MART_EXECUTIVE_OVERVIEW[total_revenue_usd])`. Renders as `$93.80M` (auto-compact formatting from the new Card visual).
4. **KPI Card: Total Units Sold** — `Total Units Sold = SUM(MART_EXECUTIVE_OVERVIEW[total_units_sold])`. Renders as `34.52M`.
5. **KPI Card: Active Stores** — `Active Stores = MAX(MART_EXECUTIVE_OVERVIEW[active_store_count])`. Renders as `10` (full footprint — all stores active every day in the period).
6. **KPI Card: Active Items** — `Active Items = MAX(MART_EXECUTIVE_OVERVIEW[active_item_count])`. Renders as `2.46K` (peak single-day item count; lower than the 3,049 in `DIM_ITEM` because M5's product lifecycle means no single day has every product active).
7. **Dual-axis line chart**: Total Revenue + Total Units Sold over `DIM_CALENDAR[calendar_date]`. PBI auto-converted to dual-axis when the two measures' scales differed enough (revenue ~$87K/day average, units ~32K/day average — same shape, different magnitudes). Visible weekly seasonality, three Christmas dips (2012/2013/2014), steady upward growth, rightmost session-6 jump.

**All measures are explicit named DAX measures**, not implicit aggregations. See `LEARNINGS.md` → "2026-05-18 — Explicit DAX measures over implicit aggregations" for the recipe-on-the-wall reasoning.

**Trend lines deferred to 5.6 polish**: dual-axis charts disable PBI's Analytics → Trend line option (version-independent constraint). Workaround would be to split into two side-by-side single-measure charts; not worth it for session 5.1 since the dual-axis chart already tells the story cleanly.

**One data observation flagged**: the chart shows a real gap between late-Jan-2014 and 2014-03-22 (session 6's two added dates). Caused by sporadic Phase 3 DAG testing rather than continuous daily runs. Closed end-of-session-5.1 via `airflow dags backfill` — ~80 dates fired back-to-back during break.

---

## DAX measure library

_(To be populated session 5.5 — time intelligence (YTD/QTD/MTD),
period-over-period (YoY, vs forecast), dynamic top-N, dynamic format
strings.)_

---

## Performance tuning

_(To be populated session 5.6 — VertiPaq compression analysis,
BI-side aggregations if needed, refresh-time benchmarks.)_

---

## Cross-page UX

_(To be populated session 5.6 — global sync slicers, drill-through
actions, theme polish via format painter, navigation buttons.)_

---

## Sections to add (Phase 5 closeout)

- Snowflake connection deep dive (session 5.1 fill-in)
- DirectQuery vs Import empirical matrix (session 5.1 fill-in)
- Semantic model walkthrough (session 5.1 fill-in)
- Page-by-page builds (sessions 5.1–5.5 fill-in)
- DAX measure library (session 5.5 fill-in)
- Performance tuning + VertiPaq results (session 5.6 fill-in)
- Cross-page UX patterns (session 5.6 fill-in)
- Five Power BI page screenshots for README (session 6.2)
