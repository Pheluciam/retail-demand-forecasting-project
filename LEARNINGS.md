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

*(to be populated during Phase 1 — provisioning, T-SQL, connection patterns,
billing controls, firewall rules)*

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

*(to be populated as decisions are made)*

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
