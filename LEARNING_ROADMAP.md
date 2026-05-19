# LEARNING_ROADMAP.md — Phil's data engineering pathway

> Captures the *learning trajectory* beyond the current project. Lives alongside
> the per-project plans (`PROJECT_PLAN.md`, `PROJECT_CONTEXT.md`) and gets
> updated as Phil's direction firms up.
>
> Created: 2026-05-13. Updated as plans evolve.

---

## Where we are

| Stage | Status | Notes |
|---|---|---|
| Project #1 — CDC NT Transport (dbt-first analytics project) | ✅ Done | Reference: `C:\dbt\cdc_nt_gtfs\` |
| **Project #2 — Retail Demand & Forecasting Pipeline** (this repo) | 🏗 In progress — Phase 4 closed (Airflow + dbt via Cosmos), Phase 5 (Power BI) next | Headline: orchestration |
| Project #3 — Financial markets pipeline (Databricks lakehouse + Data Vault 2.0) | 📋 Planned — stack locked 2026-05-19 | See "Project #3 — locked stack" section below |
| **Post-Project #3 — 6-8 week DE training journey** | 📋 Planned — design locked 2026-05-19 | Broader than the original Python-only block. See below |
| Subsequent projects | 🤔 TBD | Depends on job search outcome and direction |

---

## Project #3 — locked stack

Stack locked 2026-05-19. Builds on Project #2 muscle where useful, intentionally differentiates where portfolio variety pays off. Three projects, three distinct modeling stories.

**Repo / folder name (locked).** `financial-markets-pipeline-project` — under `C:\Users\Phil\Documents\Claude\Projects\`. Mirrors Project #2's `-project` suffix convention. Locked early to avoid mid-project folder rename causing Snowflake / Power BI / Git connection breakage (lesson from Project #2 Phase 0).

**Domain.** Financial markets. Public REST API ingestion (specific vendor TBD at Phase 0 — likely Alpha Vantage / Polygon.io / Tiingo).

**Stack:**

- **Operational source.** Azure SQL Database (MS SQL Server) — same operational-source pattern as Project #2. Python extract pulls from API → lands in MS SQL Server first.
- **Analytical platform.** Databricks (lakehouse on Delta Lake + object storage). Intentionally NOT Snowflake — portfolio differentiation.
- **Modeling pattern.** **Data Vault 2.0** in the analytical layer. Hubs (business keys), Links (relationships), Satellites (descriptive attributes + history). Native SCD, full audit lineage. Strong fit for regulated finance domain. **Genuinely different from Project #2's Kimball star.**
- **Architectural layering.** Medallion (Bronze / Silver / Gold).
  - Bronze: raw API + MS SQL ingest into append-only Delta tables.
  - Silver: Data Vault 2.0 raw vault (Hubs, Links, Satellites).
  - Gold: information marts on top of the vault for BI consumption.
- **Transformation tool.** Decide at Phase 0: dbt-databricks adapter (reuses Project #2 dbt muscle, faster ramp) vs Delta Live Tables (Databricks-native declarative ETL, stronger differentiation, new skill).
- **Orchestration.** Decide at Phase 0: Databricks Workflows (native, simpler) vs Airflow + Databricks operator (reuses Project #2 Airflow + Cosmos muscle).
- **BI.** Databricks SQL dashboards + Power BI (reuses Project #2 PBI skills).

**Portfolio modeling variety across the three projects:**

- Project #1 — dbt analytics on GTFS transit data (reference: `C:\dbt\cdc_nt_gtfs\`).
- Project #2 — Kimball star schema warehouse on Snowflake, three-tier marts (Staging → Intermediate → Warehouse → Marts).
- Project #3 — Data Vault 2.0 inside medallion lakehouse on Databricks.

**Open decisions to lock at Phase 0 of Project #3:**

- API vendor (Alpha Vantage / Polygon.io / Tiingo).
- Scope: equities only, or equities + ETFs + FX.
- dbt-databricks vs Delta Live Tables for transforms.
- Databricks Workflows vs Airflow for orchestration.
- Time horizon: bulk-load N years + daily incremental (Project #2 simulated-freshness pattern) vs live-cron.

---

## Post-Project #3 — 6-8 week DE training journey

Design locked 2026-05-19. Replaces and broadens the earlier Python-only block — same time slot, wider scope.

**Trigger.** Start while looking for work after Project #3 ships (or once Project #2 ships if job search begins earlier).

**Why.** Phil's three projects build breadth across the modern data stack but he wants to consolidate code-writing fluency and conceptual fluency before job interviews and the first day on a DE team. The original Python-only block undersold the actual gap, which is broader than language syntax — YAML, SQL, dbt, Airflow patterns, modeling, Git, CLI tooling all need active-recall practice, not just exposure.

**Goal.** Interview credibility + first-day confidence on a Data Engineer / Analytics Engineer team. NOT full mastery — Phil is not aiming to be senior-engineer fluent in 6-8 weeks. Beginner → early intermediate is the realistic target.

**Format.**

- 2-hour sessions × 3-4 sessions/week × 6-8 weeks = ~36-64 hours total
- Code-first: code walkthrough → modify-and-extend → real exercises, with concepts woven in as they come up
- Split: ~80% code, ~20% conceptual / general knowledge
- Quiz warm-up first 10-15 min of every session (see quiz design below)
- Hands-on with Phil's own Project #1 / #2 / #3 code wherever it fits — these projects are the reference codebase
- Sessions tracked in a session log; quiz progress persisted to a quiz-log file so memory carries across sessions

**Code focus (the ~80%).**

- Python — idioms (pathlib, context managers, dataclasses, f-strings), virtual envs + dependency mgmt, retries + decorators, type hints + pyrightconfig, structured logging, requests / httpx, sqlalchemy, argparse / typer, pytest
- YAML — emphasised heavily because it shows up across the whole DE stack: dbt schema files / dbt_project.yml / profiles.yml, Airflow docker-compose, GitHub Actions workflows, Docker compose, eventually Kubernetes. One YAML-fluency block pays back across every tool.
- Airflow DAG Python — TaskFlow API, decorators, idempotency, sensors, dynamic task mapping, observability
- SQL — advanced (window functions, complex CTEs), dialect differences (Snowflake / T-SQL / BigQuery / Databricks), EXPLAIN plans, partitioning + clustering
- dbt SQL + Jinja — macros, materialisations strategy, custom tests

**General-knowledge focus (the ~20%).**

- Architecture patterns — medallion, Kimball star, Data Vault 2.0, lambda / kappa, hub-and-spoke
- Data model type comparisons — when to use which
- File formats — Parquet, Delta, Iceberg, ORC, Avro — what each is optimised for
- Git workflow — branching, rebase, conflict resolution, recovery from common mistakes
- PowerShell + Linux command-line for DE
- Docker basics for DE — Dockerfiles, compose, debugging

**Suggested 8-week outline (compressible to 6 by merging Python W1+W2 and Data Quality + Git/CI weeks).**

- Week 1 — Python for DE foundations: idioms, venv + dependency mgmt, type hints + pyrightconfig, structured logging. Hands-on with existing extract scripts.
- Week 2 — Python for DE advanced: retry patterns + decorators, requests / httpx for APIs, sqlalchemy, argparse / typer CLIs, pytest fundamentals.
- Week 3 — SQL deep dive: window functions, complex CTEs, dialect differences, EXPLAIN plans, partitioning. Refactor existing dbt model SQL.
- Week 4 — dbt patterns: materialisations strategy, tests beyond not_null (custom singular + dbt-expectations), macros + Jinja, sources / snapshots / exposures.
- Week 5 — Airflow + orchestration: TaskFlow API, idempotency patterns, sensors, branches, dynamic task mapping, observability. Extend existing DAG.
- Week 6 — Modeling patterns: Kimball walkthrough of Project #2 warehouse + Data Vault 2.0 mini-example (Project #3 reinforcement).
- Week 7 — Data quality + CI/CD: custom dbt tests, Great Expectations basics, GitHub Actions for dbt CI, pre-commit hooks (sqlfluff, ruff).
- Week 8 — Git / CLI / Docker: Git deep dive (branching, rebase, conflict resolution, recovery), PowerShell + Linux scripting, Docker for DE basics.

**Quiz warm-up design.**

- First 10-15 min of each 2hr session.
- 5-8 questions per session, mixed topics, adapting difficulty.
- Question format progresses through the 8 weeks:
  - Weeks 1-2: pure multiple choice ("which of these is the correct Git command to undo the last commit while keeping changes staged?")
  - Weeks 3-4: multiple-choice scenarios ("you have a dbt model failing this test — which of these is the most likely cause?")
  - Weeks 5-6: fill-in-the-blank ("complete this Airflow DAG decorator: @____ ...")
  - Weeks 7-8: type-the-command / write-the-snippet ("write the PowerShell one-liner to find all .py files modified in the last 7 days")
- Right answer: green tick + brief explanation. Wrong: red cross + correct answer + 1-2 line reason.
- Topic mix per session, roughly:
  - 2 on concepts (architecture, modeling, file formats)
  - 2 on commands (Git / PowerShell / Linux)
  - 2 on syntax (Python / YAML / SQL)
  - 1-2 scenario-based (debug a snippet, pick the right approach)
- Cross-session memory: a `quiz-log.md` (or similar) in the training journey's project folder tracks topics nailed / missed / not-yet-seen. Claude reads it at session start, prioritises weak areas, avoids repeating recent questions. Same persistence pattern as PROJECT_CONTEXT.md works for projects.

**Folder + format.** Treat the training journey like a fourth project — its own folder following the existing `<name>-project` naming convention. Tentative name: `de-training-journey-project` (lock at Phase 0). Holds session logs, quiz log, exercise files, any mini-deliverables.

**Tooling: Claude Code (not Cowork).** Locked 2026-05-19. Reasons: (a) the journey is 80% code and terminal-native by design — Claude Code IS the terminal-native DE workflow, simulating job-day-1 conditions; (b) quizzes work fine in terminal (numbered MCQ → typed answer → typed command progression); (c) markdown persistence pattern (quiz-log.md, session log) works identically in Cowork and Code, so no continuity loss. Cowork stays useful for occasional admin/planning sessions and the final portfolio-publishing pass.

**What this journey is NOT.**

- A "learn computer science" detour — no data structures / algorithms drills. Strictly DE-applicable.
- A portfolio project in itself — it's a learning sprint with internal artefacts, not a public deliverable. (Optional: publish a sanitised version at the end as a "what I learned" GitHub repo.)

**Open decisions to lock at training journey Phase 0:**

- 6 weeks vs 8 weeks (depends on job-hunt timing).
- Folder name (`de-training-journey-project` is the working name).
- Whether to publish a sanitised public version as a portfolio artefact.
- Initial quiz topic seed list — concrete starter pool of ~50 questions across the 4 topic buckets.

---

## Career target context

Per Phil's own framing:

- Realistically aiming for **Analytics Engineer**, **Senior Data Analyst with pipeline work**, or **BI Engineer** roles immediately after Project #2 ships.
- The 6-8 week DE training journey opens the door to **mid-level Data Engineer** roles by the end of Project #3 + journey.
- Long-term direction: Data Engineer.

---

## Notes / changes

- 2026-05-13 — Initial creation. Six-week Python block captured per Phil's mid-Phase-2 reflection (after the "what does a real DE actually do?" conversation).
- 2026-05-19 — Project #3 stack locked. Finance API → Azure SQL Server → Databricks lakehouse, with Data Vault 2.0 modeling inside a Bronze/Silver/Gold medallion. Locks portfolio modeling variety: Kimball (#2) + Data Vault (#3) are genuinely distinct stories. Five open Phase 0 decisions captured.
- 2026-05-19 — Project #3 folder name locked as `financial-markets-pipeline-project` (under `C:\Users\Phil\Documents\Claude\Projects\`). Locked early to prevent mid-project rename — Project #2 had folder-rename connection breakage that we're not repeating.
- 2026-05-19 — Post-Project #3 training journey design locked. Replaces the earlier Python-only block with a broader 6-8 week, code-first, quiz-warm-up program covering Python + YAML + Airflow DAG Python + SQL + dbt + modeling + Git/CLI/Docker. Hands-on with Phil's own project code. 80/20 code-to-concept split. Beginner → early intermediate target. Quiz progression: multiple choice → fill-in-blank → type-the-command across weeks 1-8. Cross-session memory via a quiz-log file. Tentative folder name `de-training-journey-project`. Four open decisions captured for Phase 0.
- 2026-05-19 — Training journey tooling locked as Claude Code (not Cowork). Terminal-native workflow simulates real DE job conditions, quizzes work in-terminal, markdown persistence identical across tools. Cowork stays available for occasional admin/planning sessions.
