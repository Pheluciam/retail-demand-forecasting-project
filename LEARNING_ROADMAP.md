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
| **Project #2 — Retail Demand & Forecasting Pipeline** (this repo) | 🏗 In progress | Headline: orchestration |
| Project #3 — financial markets / lakehouse | 📋 Planned | API ingestion, lakehouse/medallion architecture |
| **Post-Project #3 — 6-week Python deep dive** | 📋 Planned | See below |
| Subsequent projects | 🤔 TBD | Depends on job search outcome and direction |

---

## Post-Project #3 — 6-week focused Python learning block

**Trigger:** start after Project #3 ships.

**Why:** Phil's self-assessment is "I can read Python at intermediate level but I cannot write it from scratch." This is the single biggest gap between his current profile and a strong Data Engineer / mid-level Analytics Engineer position. Pure DE roles need at least journeyman-level Python; even Analytics Engineer roles benefit from confidence here. Closing the gap deliberately — rather than picking it up incidentally — is faster and more interview-defensible.

**Primary focus (~80% of the time):**

- Python scripting for **data engineering specifically** — not "Python in general"
- Working from real-world DE patterns: extract jobs, validation scripts, small CLIs, retry/idempotency patterns, structured logging, type hints, `pathlib`, `dataclasses`, `argparse`, etc.
- Best practices: virtual environments, dependency management (`pip` / `uv` / `poetry`), pinned vs floating versions, lock files
- Reading and writing tests with `pytest`
- The DE-relevant standard-library + ecosystem: `pandas`, `pyarrow`, `requests`, `httpx`, `sqlalchemy`, cloud SDKs (`boto3`, `azure-sdk-for-python`), the Snowflake connector

**Secondary focus (~20% of the time, woven through):**

- Git — branching, merging, rebasing, resolving conflicts, working from a feature branch + PR, `.gitignore` patterns, recovering from common screwups
- PowerShell / command-line — file navigation, piping, environment variables, scripting basics, common Linux-equivalent commands (since most real DE work happens on Linux servers)

**Format ideas (to discuss when we get there):**

- One concept per session, hands-on
- Real DE-style mini-projects: write an extract from a public API; validate a CSV; build a tiny scheduled job
- Code-review-driven — Claude writes a short script, walks through it line-by-line, then Phil modifies and extends. Builds writing fluency on top of reading fluency.

**What this block is NOT:**

- A "learn computer science" detour. No data structures / algorithms drills. Strictly DE-applicable.
- A separate portfolio project. It's a learning sprint between project deliverables, not a deliverable itself.

---

## Career target context

Per Phil's own framing:

- Realistically aiming for **Analytics Engineer**, **Senior Data Analyst with pipeline work**, or **BI Engineer** roles immediately after Project #2 ships.
- The 6-week Python block opens the door to **mid-level Data Engineer** roles by the end of Project #3 + block.
- Long-term direction: Data Engineer.

---

## Notes / changes

- 2026-05-13 — Initial creation. Six-week Python block captured per Phil's mid-Phase-2 reflection (after the "what does a real DE actually do?" conversation).
