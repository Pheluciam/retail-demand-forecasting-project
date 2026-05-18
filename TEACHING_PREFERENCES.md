# Teaching Preferences — Phil

> Read this at the start of every Cowork session, alongside `PROJECT_CONTEXT.md`.
> This file is about _how_ I want Claude to work with me — not what we're building.
> Last updated: 2026-05-18

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
- **UI walkthroughs in any new tool: 1-2 steps per chunk, 2-3 absolute max.** Especially Power BI Desktop. Phil prefers walking through dialogs one screen at a time, not getting a 4+ step plan that requires backtracking when one step lands differently than predicted (different button label, missing field in his free Desktop edition, dialog already showing different state, etc.). Stop after 1-2 steps, wait for confirmation or screenshot, then proceed. The "yell when done" pattern only works for genuinely linear tasks like data loads — not for multi-dialog UI flows. Added 2026-05-18 (Phase 5 session 1).
- **Commit messages: subject line + max 3 short body lines. Tight, professional, senior-DE style.** Subject ~50 chars (72 max), imperative form, no trailing period. Body explains WHY, not WHAT (the diff shows what); each body line <72 chars; if bullets are used cap at 3-4 items. The PROJECT_CONTEXT closeout block is the place for detail — the commit message is the index entry, not the change log. Example good: `"Phase 5 session 1: Power BI Executive Overview page"` + 2-3 line body on the WHY of composite mode. Example bad (what Claude shipped at session 5.1 close): subject + 10-bullet exhaustive body restating every file changed — reads as unprofessional and noisy. Added 2026-05-18 (Phase 5 session 1 close, captured from Phil's feedback).
- **Chat response length: tighter than Claude's been writing through Phase 5 session 1.** Default to under ~150 words per response unless the user explicitly asks for depth or a write-up. Skip preamble ("Great catch! Let me think about this..."), skip caveats and trailing "let me know if..." prompts. Just do the thing or ask the next clear question. Even when bullet points are warranted, cap at 3-4 per response. Phil will ask for more depth if he wants it. Added 2026-05-18 (Phase 5 session 1 close, captured from repeated Phil feedback through the session that responses were walls of text).

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
- **BI tool: Power BI Desktop only — NO Power BI Service licence.** Important framing: Power BI **Desktop is universally free**; there is no paid Desktop tier. The free/paid split is **Desktop vs Service** (Service is the paid cloud platform for sharing). Phil has full Desktop, no Service. Practical implications for instructions: no published-to-Service features (scheduled refresh, RLS in Service, workspaces, apps); deliverable is the `.pbix` file + screenshots in README, not a Service link. Claude should never reference Service-only steps for this project. **Separately**, Phil's Desktop UI may differ from Claude's mental model because PBI Desktop ships frequent UI updates (new visuals promoted from preview to default, old ones hidden, ribbon items moved between sections). Examples seen this session: "Recent Sources" not visible in Get Data dropdown; data-load progress shows a spinner not a row counter; the new Card visual replaced the classic Card as default (Nov 2025 GA), so only one "Card" option appears in the Visualizations pane. **Discipline rule**: when an instruction references a specific PBI UI element (button, visual, menu path, dialog field), Claude should either ask Phil to confirm what he sees BEFORE prescribing clicks, or web-check the current state of that UI element rather than asserting from memory. Added 2026-05-18 (Phase 5 session 1).

## Anything else Claude should know

- Teach slow, but summarise mainly, Ill pick it up from doing it.
- Will need quite a bit of clarifications with Python.
- Git and PowerShell: teach incidentally as we work — no dedicated sessions. When we hit a `git commit`, branch, or shell command for the first time, briefly explain what it does and why, then move on. I'll pick these up by repetition through the project work.
- **PowerShell commands: one command per code block, always.** Never bundle multiple commands into a single block. One block = one copy-paste = one execution. Even when commands chain naturally (e.g. `git add` then `git commit`), keep them in separate blocks. Added 2026-05-15 (Phase 4 session 2).
- **End-of-session git cadence: one bundled commit per session.** Don't artificially split work into multiple logical commits for "clean history" — it adds back-and-forth and noise. One `git add` + one `git commit` + one `git push` per session closeout. Within-session pushes only when explicitly requested or when there's a real reason to back the work up to remote mid-session. Added 2026-05-15 (Phase 4 session 2).
- **Snowsight diagnostic queries: one query per code block, run separately.** Same pattern as PowerShell. When Claude proposes multiple verification queries (parity check, sample eyeball, distribution sanity, etc.), present each as its own fenced code block so Phil can paste-and-run them one at a time. Batched results in Snowsight's history view are hard to scan after the fact. Added 2026-05-16 (Phase 4 session 3).
- **Default to "most professional" for judgement calls.** When picking between options (commit message style, naming conventions, file layout, code structure, test coverage depth, etc.), Claude defaults to the most professional approach a senior data engineer would ship in production — with a small offset for the learning-project context, meaning Claude still picks the professional default but leans toward the version that surfaces more *teaching* in the surrounding conversation (verbose-in-chat layer, walkthrough docs, explicit reasoning on design calls). The deliverable should look like a senior engineer produced it; the conversation building it can lean teaching-heavy. Added 2026-05-16 (Phase 4 session 4 close).
- **Power BI architectural discipline rules — locked 2026-05-18 after session 5.2 mid-session reset.** A measure-architecture bug surfaced when 4 measures created on a pre-aggregated mart (which has no relationship to item/store dims) showed the same value for every category when sliced by `cat_id`. Discipline rules now in force for every PBI session: (1) **Before prescribing any PBI step, verify state** — never assume from prior session's closeout text. If unsure whether a measure exists / a relationship is active / a column has a specific name, ASK Phil or web-check. (2) **Measures live on a dedicated hidden `_Measures` table** — never on data tables. (3) **Measures aggregate the FACT**, never the pre-aggregated mart. The mart is hidden in PBI; if a formula references a mart column, it's wrong. (4) **Dims joined to a DirectQuery fact must be in Dual storage mode** — pure Import creates limited (weak) relationships per SQLBI / Marco Russo. (5) **When dragging a field into a visual, use the named measure from `_Measures`**, never a raw column. Implicit `Sum of <column>` aggregations are a red flag. (6) **For destructive PBI changes (delete measure, change storage mode, hide table): explain the rollback path first**, then proceed. The full locked plan for sessions 5.2-5.6 lives in `POWERBI_PLAYBOOK.md` at repo root — read it first at the start of every Phase 5 session before proposing any step.
- **Don't suggest 5-6 hour unattended runs when a 25-min alternative exists.** Lesson learned 2026-05-18 (Phase 5 session 5.2): Claude proposed running the full Airflow extract→verify→dbt→verify_dbt chain 68 times for a backfill (~5-6h sequential, ~1-2h parallel) when the actual professional pattern is `--task-regex extract_one_day -i` on the backfill (~20-25 min). Always lead with the shortest professional approach; flag the duration explicitly before any command runs; offer 2-3 explicit options when scope-of-work is non-trivial.
- **Analogies for architectural and structural explanations.** When explaining how components in the stack talk to each other (Snowflake ↔ Airflow ↔ dbt, container boundaries, volume mounts, environment isolation, why a specific shell command exists in the chain), lead with a real-world analogy — a factory floor, a restaurant kitchen, an office layout, an assembly line, whatever fits the topology — then layer the technicalities on top. The analogy is the *frame* that makes the technical detail land; the technicalities still need to be there. Especially useful for: how environments are isolated (containers, venvs, mounts), how data flows between tools (warehouse ↔ orchestrator ↔ transformer ↔ BI), why a specific config or command is needed and what would break without it, what a Docker rebuild or restart actually does to the running system. Code walkthroughs themselves don't need analogies — those work fine as verbose-in-chat with comments-above-the-line. The pattern: pick a concrete real-world setting, map the project's components onto roles within it, then map the technical action onto a physical action within that setting. Examples that have landed well so far: **factory floor** (Airflow = shift supervisor with clipboard, dbt = transformation cell, dbt models = machines, Cosmos = engineer copying the wiring diagram onto the supervisor's clipboard); **locker-and-rulebook frame** for dependency management (Docker venvs = separate lockers, Airflow's constraints file = main rulebook, dbt = a different supplier needing its own rulebook in its own locker); **window-in-the-wall frame** for volume mounts (the worker inside the container can't walk out to the host, so we cut a view-only window through the wall to a specific folder on the host). Added 2026-05-17 (Phase 4 session 6).
