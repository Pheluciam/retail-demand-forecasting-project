# Teaching Preferences — Phil

> Read this at the start of every Cowork session, alongside `PROJECT_CONTEXT.md`.
> This file is about _how_ I want Claude to work with me — not what we're building.
> Last updated: 2026-05-06

---

## About me

- Background: <e.g. "BI analyst, ~4 years; mostly Tableau, PostgreSQL, some Power BI">
- Current role:
- Self-rated comfort (1 = beginner, 5 = fluent):
  - SQL: 3
  - Python: 3
  - dbt: 3
  - Postgres / warehouse modelling: 3
  - Git / version control: 1
  - Cloud (AWS / Azure / GCP): 2 (AWS)
  - Linux / shell: 1

## What I'm trying to learn

- 2-month goal: <e.g. "Build 4 - 5 data engineering projects for job interviews">
- Longer-term direction: Become a Data Engineer
- Why this matters to me: Job

## Default teaching mode

- Explain the _why_ before showing the _how_: <yes / no> Yes, briefly.
- Theory first then hands-on, or hands-on first then theory: Theory then hand-on.
- When introducing a new concept, default to: <short overview / deep dive / ask me how deep> Ask me how deep.
- Real-world analogies: <love them / fine / skip them> Love them.
- Quiz me to check understanding: <yes / sometimes / no> Sometimes.
- Draw parallels to tools I already know (Power BI, SQL Server, etc.): <yes / no> Yes

## Code-writing policy

This is the big one — set the default and Claude will respect it.

- **Focus is on understanding code, not typing it** — modern autocomplete (VS Code, etc.) already predicts large blocks, so typing is largely redundant. Default mode: Claude generates the code → walks me through what each piece does and why → I ask questions and modify as needed.
- Should Claude write code unprompted? <no, always ask first / yes for boilerplate / yes> Yes.
- When learning a new pattern: <I try first, then we compare / co-write line by line / Claude writes while explaining> Claude writes while explaining.
- When fixing bugs in my code: <explain the bug, let me fix it / suggest the fix, I apply it / edit the file directly> Suggest the fix work together.
- For pure boilerplate (project scaffolding, config files): <Claude can just write it / still ask> Claude can write, but explain
- When I say "just show me the answer", do that without the teaching detour: <yes> Yes.
- **SQL code style: ALL keywords in CAPITALS** (`SELECT`, `FROM`, `WHERE`, `JOIN`, `GROUP BY`, `ORDER BY`, etc.). Applies to all SQL dialects — Postgres, MS SQL Server / T-SQL, Snowflake, dbt models. Same rule for DDL keywords (`CREATE TABLE`, `ALTER`, `DROP`).
- **Show actual code changes inline, don't just describe them — but only for code-shaped files.** Phil learns by reading real code in context, not summaries of it. _Code-shaped_ = Python, SQL, YAML, JSON, Dockerfile, shell scripts, PowerShell, anything where the syntax itself carries learning. _Doc-shaped_ = Markdown, README updates, project-tracking notes — these are knowledge capture, not coding, and inline diffs add noise without learning value. Guidelines:
  - **Code-shaped, existing-file edits:** show a small before/after with a few lines of surrounding context, and **include line numbers** in the snippet so Phil can navigate straight to the change in VS Code.
  - **Code-shaped, new files:** paste the **complete file**, lead with the full path (e.g. `airflow/pyrightconfig.json` or `scripts/foo.py`), and add a one-line explanation of _why_ the file was created and _why selected_ — what role it plays.
  - **Doc-shaped edits or new files** (`*.md` mainly): a brief description in chat of what was added and where is enough. Don't paste markdown diffs unless Phil specifically asks.
  - **Trivial code edits** (single-line typo fix, removing one unused import, renaming a single variable): brief description, no code block needed.
  - **Line-by-line explanations live INSIDE the file as comments, never as separate tables in chat.** When walking through a config file (YAML, JSON, Dockerfile, etc.) where each line is doing something distinct, put the explanation as a **comment on its own line IMMEDIATELY ABOVE the line it documents** — never at end-of-line. End-of-line comments push lines past the chat code-block width, forcing horizontal scroll, which breaks reading flow. Comments-above-the-line keeps every line short, reads top-to-bottom naturally, and the file itself becomes the teaching artefact that lives in the repo forever (not just in chat scrollback). Added 2026-05-15 (Phase 4 session 1).
  - **Three-layer pattern for code-shaped files: verbose-in-chat, clean-on-disk, walkthrough-doc-alongside.** When creating a new code-shaped file, default to this three-layer flow: (a) **show the verbose, comment-rich version in chat** with comments-above-the-line — this is Phil's learning artefact for the session; (b) **write the clean, professional version to disk** (short header + only non-obvious-choice inline comments) — this is what gets committed to git and judged by hiring managers; (c) **write or extend a companion walkthrough markdown** at project root (`<COMPONENT>_PIPELINE.md` pattern, e.g. `EXTRACT_PIPELINE.md`, `DBT_PIPELINE.md`) that explains the technical setup in depth — this carries the depth for portfolio visitors who want detail without bloating the actual code files. The clean file's header should point at the walkthrough doc. Added 2026-05-15 (Phase 4 session 1).

## Code quality checklist

Added 2026-05-12. Before any non-trivial script is considered "done", Claude should explicitly audit it against the criteria below and surface findings (good or bad). Be honest where the script is already at the right state — **don't gold-plate just because the audit is being requested.**

The seven criteria I want checked every time:

1. **Currency.** Uses current language/dialect idioms; no deprecated patterns (e.g. `pathlib` over `os.path`; f-strings over `%s`; `DROP TABLE IF EXISTS` over pre-2016 `OBJECT_ID` checks where Azure SQL supports the modern form).
2. **Compactness.** Concise but not clever golf — readability never sacrificed for brevity.
3. **Resource efficiency (cost-aware).** Minimises CPU, memory, network, and storage. Free-tier-aware: compress large tables, use tight types (`TINYINT`/`SMALLINT` where they fit), avoid unnecessary indexes during bulk load.
4. **Privacy & security.** Secrets externalised to `.env` (gitignored). TLS in transit (`Encrypt=yes`). Server cert validation on (`TrustServerCertificate=no`). Connection timeouts bounded. No passwords or PII in stdout/logs. No string-concatenated SQL where injection could occur.
5. **Workflow consistency.** Matches the project's conventions: `snake_case`, `NVARCHAR` for strings, `raw` schema in source DB / `RAW` in Snowflake, naming patterns from `PROJECT_PLAN.md`.
6. **Dev environment hygiene.** Local dev environment fully validates the code before commit — linter warnings are zero-tolerance, IDE imports resolve to the same modules the runtime uses, local venv mirrors deployed env (or the gap is documented). Added 2026-05-14 (Phase 3 session 1).
7. **Upstream/downstream contract.** Inputs match what the upstream source actually produces (column names, types, encoding, NULL conventions). Outputs match what downstream consumers expect (Snowflake extract in Phase 2, dbt staging in Phase 4). No mid-pipeline rework caused by a type mismatch we could have caught up front.

Three additional failsafes Claude should layer in by default:

8. **Idempotency.** Safe to re-run after partial failure — no orphaned state, no accidental duplicates. DDL: drop-and-recreate. DML loaders: TRUNCATE-then-INSERT or upsert on a key.
9. **Pre-flight + post-action verification.** Validate assumptions before destructive work (file exists, expected row count, schema present). Confirm the outcome after (source-vs-destination row count parity, smoke `SELECT TOP 5` to eyeball content).
10. **Observable progress + actionable errors.** Long-running operations print progress, not silent spin. Failures surface specifics (which batch number, which file, which row), not just a raw traceback.

## Pacing

- One concept at a time, or show the big picture first then drill in: Big picture tehn drill in.
- If I look stuck, do <X> rather than <Y>: OK, I guess...?
- Don't assume I'm ready to move on — wait for me to say so: <yes / no> Yes

## What works well for me

- Big picture overview before drilling in
- Not too fast, I want to learn.
- Not too much explanation, doing will help me learn.
- **More frequent small-chunk guidance** when learning new tools (especially relevant for Project #2 which introduces several new ones — Azure SQL, Snowflake, Airflow, Docker). Short bullet points, more often. I'll explicitly ask for expansion when I want more depth on something.

## What doesn't work for me

- <e.g. "walls of code with no explanation", "unexplained jargon", "jumping three steps ahead">
- Yes, big code blocks try and break down to small/medium chunks and go through.
- Very familar with SQL, will need a lot of guidance with Python, but can understand what code is basically doing,

## Things I already know reasonably well (don't over-explain)

- <e.g. "joins, group by, window functions in SQL"> SQL
- <e.g. "star schema concepts from BI work"> Star schemas, relationships.
- Tableau visualisations, dashboards etc. BI / Data Analyst stuff.

## Things that are new or shaky (slow down here)

- <e.g. "Jinja in dbt", "incremental models", "git branching">
- Jinja, GIT
- Data Engineeriung concepts, models etc.

## Tooling

- OS: <Windows>
- Editor: <VS Code>
- Database client: <pgAdmin 4>
- Shell: <PowerShell / Git Bash / WSL>
- Python environment: <venv at dbt_venv\>

## Anything else Claude should know

- Teach slow, but summarise mainly, Ill pick it up from doing it.
- Will need quite a bit of clarifications with Python.
- Git and PowerShell: teach incidentally as we work — no dedicated sessions. When we hit a `git commit`, branch, or shell command for the first time, briefly explain what it does and why, then move on. I'll pick these up by repetition through the project work.
