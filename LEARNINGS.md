# LEARNINGS.md — Retail Demand & Forecasting Pipeline

> A running journal of what I'm learning on Project #2.
> First entry: 2026-05-09.

This is my second data engineering project, building on what I learned in Project #1
(CDC NT Transport). The point of this document isn't to look polished. It's to capture
the real moments where something clicked, broke, or made me rethink an assumption,
so I can refer back to it in interviews and on future projects.

---

## Project summary

End-to-end data engineering portfolio project building a production-grade retail
demand-planning analytics platform. Real Walmart sales data (M5 Forecasting dataset)
is ingested from Azure SQL Database into Snowflake via scheduled Airflow jobs,
transformed through a partitioned star schema with dedicated marts using dbt,
and surfaced as a five-page Power BI dashboard for an operations / S&OP audience.

Headline focus: **orchestration**. Pipeline runs end-to-end on a schedule with proper
failure handling, tests, and CI — not button-pressed like Project #1.

---

## Technical learnings

> Sections below will fill in as work progresses. Each entry should capture what
> happened, what was new, and what I'd do differently. Project #1 examples for
> reference are in `C:\dbt\cdc_nt_gtfs\LEARNINGS.md`.

### Azure SQL Database

**Provisioning (2026-05-12 session)**

- **"Azure SQL" in Marketplace is a hub, not a product.** It splits into SQL databases, Managed Instance, SQL VMs. We want **SQL databases** (Single database). The Azure UI also pushes **Hyperscale** as the headline option — that's a different (more expensive) tier, NOT what we want. Plain General Purpose Serverless is correct for a project this size.
- **Free Azure SQL Database offer exists and is excellent.** 100,000 vCore-seconds + 32 GB data + 32 GB backup free **per month for the lifetime of the subscription**. One free database per subscription. Critical safety: when free limits are hit, you can configure "auto-pause until next month" with **Overage billing: Disabled**, meaning zero risk of unexpected charges. This is dramatically better than the paid path I'd planned for.
- **Logical server vs database.** Two distinct concepts. The **server** is the security/firewall boundary with a globally unique public hostname (`*.database.windows.net`); the **database** lives inside it. Server names must be globally unique across all Azure customers. Used `sql-retail-demand-fc-phm` (phm suffix = initials).
- **Region — Australia East is the AU primary.** Microsoft puts new services there first; Australia Southeast (Melbourne) is the paired DR region with thinner service coverage. Free offer was available in Australia East.

**Firewall**

- During provisioning, the Networking tab has an **"Add current client IP address"** toggle — this creates the firewall rule for you. Public IP captured this session: `115.69.3.187`. Will need to add new rules when working from other networks (mobile hotspot, etc.).
- **"Allow Azure services and resources to access this server" = Yes** allows other Azure services (Azure Functions, Logic Apps, etc.) to connect. Needed if we later integrate with anything Azure-side.

**Authentication**

- **SQL authentication** picked over Microsoft Entra. Reason: our Python scripts (Phase 2 onwards) need a username/password pair to connect. Entra would require setting up an Entra admin on the server and using token-based auth in Python — extra complexity for no portfolio benefit. SQL auth with `sqladmin` + strong password is the right call.
- Admin password must satisfy 3-of-4 complexity (upper / lower / digit / symbol) and 8–128 chars.

**Cost controls**

- Set up a **Resource Group-scoped budget** at $50 AUD before provisioning anything. Budgets are alerts only (not hard caps) — Azure has no true spending hard cap on pay-as-you-go subscriptions.
- For the Free offer, the practical hard cap is "Overage billing: Disabled" — DB pauses, no charges.
- Budget thresholds set: 50%, 80%, 100% Actual + 100% Forecasted. Forecasted is the early-warning alert that catches runaway spend before it actually hits the cap.

**Connection testing**

- **Portal's Query editor (preview)** is excellent for the first connection sanity check — browser-based, no client install. Sign in with SQL auth (`sqladmin` + password), paste `SELECT @@VERSION;`, hit Run. Result confirmed Azure SQL 12.0.2000.8.
- For Phase 2 onwards we'll switch to Azure Data Studio or VS Code's mssql extension for richer querying.

**Secrets management pattern**

- Created `.env` (gitignored) holding real secrets + `.env.example` (committed) as a template. Loaded in Python via `python-dotenv` → `os.getenv()`. Same pattern will extend to Snowflake creds in Phase 2 and Kaggle in any scripted download.
- ⚠️ **Slip this session:** Claude echoed Phil's real password back in a chat message. The password is still valid; risk is low since the transcript is between Phil and Claude (not public), but a clean fix is to rotate the password in Azure portal and update `.env`.

### Snowflake

*(to be populated during Phase 2 — warehouse / database / schema setup, COPY INTO,
query patterns, cost management)*

### Airflow

*(to be populated during Phase 3 — Docker compose stack, DAG patterns, scheduling,
failure handling, secrets management)*

### dbt (advanced from Project #1)

*(to be populated during Phase 4 — incremental models, partitioning, dbt_utils,
tests, marts layering)*

### Power BI (advanced from Project #1)

*(to be populated during Phase 5 — explicit DAX measures, cross-page slicers,
drill-throughs, format painter, themes)*

### Docker

*(to be populated as encountered — containerisation patterns, docker-compose,
networking between containers)*

### Git / GitHub Actions

*(to be populated as encountered — branching, PRs, CI workflows, sqlfluff lint)*

---

## Mistakes & diagnoses

> Each entry: Symptom → Diagnosis → Fix → What this taught me.
> Capture mid-project, not just at end. Project #1 had ~6 of these — this section
> is where future-me looks first when something goes wrong.

*(to be populated as we hit and fix problems)*

---

## Design decisions

> Each entry: what was considered, what was chosen, what was the trade-off accepted.
> Particularly important for: dbt-vs-DAX-vs-marts calls, partitioning strategy,
> incremental model design, surrogate key approach.

### 2026-05-12 — Simulated freshness via date-partitioned extraction (Option B)

**Considered:**
- Option A: Load all 6 years of M5 into Azure SQL once, have Airflow run nightly over the full set. Honest about static data in the README.
- Option B: Same one-time bulk load into Azure SQL, but the Airflow DAG extracts ONE new date slice per scheduled run, advancing through M5 history as if it were a live source.

**Chosen:** Option B.

**Trade-off accepted:** Slightly more complex extract script (must accept a `run_date` parameter and filter `WHERE sale_date BETWEEN data_interval_start AND data_interval_end`) in exchange for a dramatically more credible orchestration story. Incremental dbt models, dbt tests, and failure alerts all have something *real* to fire on — each Airflow run actually processes new rows, instead of looping over the same static set every night.

**Why this matters for the portfolio:** the headline of Project #2 is orchestration. Option A reduces the schedule to theatre. Option B makes "runs daily, picks up new data, transforms, tests, alerts on failure" a true statement.

### 2026-05-12 — Airflow stays in Phase 3 (before dbt and Power BI)

**Considered:** Build dbt and Power BI manually first (Phases 3 + 4), then wrap everything in Airflow at the end.

**Chosen:** Keep the plan's ordering — Airflow in Phase 3, dbt in Phase 4, Power BI in Phase 5.

**Trade-off accepted:** Airflow lands before there's a "full" pipeline to schedule — but by end of Phase 2 there's already a working Python extract script, which is exactly what gets wrapped in the first DAG. New layers (dbt, then Power BI refresh) bolt onto the existing DAG as additional tasks. This matches how production pipelines actually grow: orchestration is built early and small, then extended, not bolted on at the end.

**Why this matters:** the headline deliverable shouldn't be the last thing built. If Airflow goes last and the project runs out of energy, the portfolio piece loses its differentiator from Project #1.

---

## Pipeline orchestration

> Project #1 was manual. Project #2's headline is orchestration. This section
> captures the orchestration design and lessons learned implementing it.

*(to be populated during Phase 3)*

---

## What I'd do differently next time

> Lessons that should carry forward to Project #3.

*(to be populated through the project, finalised at the end)*

---

## Open questions / things still shaky

> Things I haven't fully understood yet. Useful for spotting where to dig deeper
> in Project #3, or for interview prep where I should expect questions.

*(to be populated as questions come up)*

---

## Carry-forward to Project #3

> What I want to do from day one of the financial markets / lakehouse project.

*(to be populated near end of Project #2)*
