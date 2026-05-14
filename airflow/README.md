# Airflow Stack — Local Docker

Local Apache Airflow stack for the retail-demand-forecasting pipeline. The
DAG `m5_daily_extract` wraps `scripts/extract_azure_to_snowflake.py` and
runs it once per day (incremental mode) on a schedule.

This README is a quick-start cheatsheet. Architecture details and design
rationale live in `LEARNINGS.md` under the "Airflow" section.

---

## Components

| Container          | Image                            | Role                                                |
| ------------------ | -------------------------------- | --------------------------------------------------- |
| `postgres`         | `postgres:15`                    | Airflow's metadata DB (DAG runs, task state, users) |
| `airflow-init`     | (custom)                         | One-shot: runs `airflow db migrate` + creates user  |
| `airflow-webserver`| (custom)                         | UI on http://localhost:8080                         |
| `airflow-scheduler`| (custom)                         | Parses DAGs, schedules + executes tasks             |

Custom image = `apache/airflow:2.10.3-python3.11` + Microsoft ODBC Driver 17
+ our `requirements-airflow.txt` (pyodbc, python-dotenv,
snowflake-connector-python[pandas]).

Executor: **LocalExecutor** — each task runs as a subprocess on the
scheduler. No Celery / Redis. Fine for a single-DAG portfolio project.

---

## Daily operation

All commands below run from this `airflow/` directory. Docker Desktop must
be running first (whale icon in taskbar, settled to solid).

### Start the stack

```powershell
docker compose up -d
```

Brings up postgres → init → webserver + scheduler. Takes ~60s for the
healthchecks to settle. The init step is idempotent — safe to re-run.

### Stop the stack

```powershell
docker compose down
```

Stops and removes the containers. The postgres data volume persists by
default — Airflow's history is kept between restarts.

### Stop and wipe everything (incl. metadata DB)

```powershell
docker compose down -v
```

The `-v` removes named volumes including `postgres-db-volume`. Next start
will re-run `airflow db migrate` from scratch. Use this when something is
weird and you want a clean reset.

### Check container health

```powershell
docker compose ps
```

All three long-running containers should show `Up X (healthy)`. Init won't
be listed once it has exited successfully.

### Tail logs

```powershell
docker compose logs -f airflow-scheduler   # follow the scheduler
docker compose logs -f airflow-webserver   # follow the webserver
docker compose logs --tail=50 airflow-init # see what init did
```

`Ctrl-C` stops following; containers keep running.

### Rebuild the image (after editing Dockerfile or requirements-airflow.txt)

```powershell
docker compose build
docker compose up -d
```

Layer cache keeps subsequent rebuilds fast unless you change an early step.

---

## Web UI

- URL: http://localhost:8080
- Username: `airflow`
- Password: `airflow`

Both creds are set in `docker-compose.yml` via `_AIRFLOW_WWW_USER_*` env
vars. Change them there if you ever want different creds.

The UI is purely a local dev tool. It's not exposed beyond your machine.

---

## Where things live

| Path                                | What it is                                              |
| ----------------------------------- | ------------------------------------------------------- |
| `Dockerfile`                        | Custom image recipe                                     |
| `docker-compose.yml`                | The stack definition                                    |
| `requirements-airflow.txt`          | Extra Python deps installed into the custom image       |
| `dags/`                             | DAG `.py` files. Scheduler watches this folder.         |
| `dags/m5_daily_extract.py`          | The first DAG — wraps the extract script               |
| `logs/`                             | Task logs land here. Gitignored.                        |
| `plugins/`                          | Custom plugins (empty for now)                          |
| `../scripts/`                       | Mounted read-only at `/opt/airflow/scripts` inside    |
|                                     | containers. DAG imports the extract module from here.   |
| `../.env`                           | Loaded via `env_file:` — provides Azure SQL +           |
|                                     | Snowflake creds inside containers.                      |

---

## Common gotchas

- **`failed to connect to the docker API`** → Docker Desktop isn't running.
  Start it from the Start menu, wait for the whale icon to settle, retry.
- **Port 8080 already in use** → something else (Jupyter, etc.) has the
  port. Either free it up or change `"8080:8080"` to `"8081:8080"` in
  `docker-compose.yml`.
- **`docker compose up` fails because admin user exists** → shouldn't
  happen since we made init idempotent (see comments in
  `docker-compose.yml`). If it does, `docker compose down -v` resets the
  metadata DB.
- **Webserver / scheduler show `(unhealthy)` after 2+ minutes** → check
  logs (`docker compose logs airflow-scheduler`). Most common cause is a
  parse error in a DAG file in `dags/`.
- **DAG isn't appearing in the UI** → scheduler hasn't picked it up yet
  (re-parse happens every ~30s) or there's a parse error. Check
  `docker compose logs airflow-scheduler` for tracebacks.
- **Times displayed in the UI are UTC** → Airflow default. Intentional.
