# =============================================================================
# Custom Airflow image -- extends the official apache/airflow base with the
# Python dependencies and the Microsoft ODBC driver that our M5 extract
# pipeline (scripts/extract_azure_to_snowflake.py) needs at runtime.
#
# Why a custom image rather than _PIP_ADDITIONAL_REQUIREMENTS in compose:
#   * Reproducible -- the same image rebuilds the same way every time.
#   * No "for testing only" warnings in the scheduler logs.
#   * apt-installable system packages (the ODBC driver) can't be added
#     at runtime via _PIP_... anyway -- they need to be baked in.
#
# Base image notes:
#   * apache/airflow:2.10.3-python3.11 is based on Debian 12 (bookworm).
#   * Tagged version, not `latest`, so the build is deterministic.
# =============================================================================

# Single source of truth for the Airflow + Python versions. The same ARGs
# drive both the base image tag (FROM line below) and the constraints URL
# (further down). Bump in one place; no drift between layers.
#
# Docker quirk: ARGs declared BEFORE the FROM line are "global" and are
# consumed by FROM, but the values are not visible in the subsequent build
# stages unless re-declared *after* FROM. We do that re-declaration further
# down before using them again.
ARG AIRFLOW_VERSION=2.10.3
ARG PYTHON_VERSION=3.11

FROM apache/airflow:${AIRFLOW_VERSION}-python${PYTHON_VERSION}

# -----------------------------------------------------------------------------
# System packages (root for apt).
# -----------------------------------------------------------------------------
# pyodbc is a Python wrapper around the system-level ODBC driver, so the
# driver itself has to be installed as a Debian package. Microsoft's
# instructions for Debian 12: import their GPG key, add their apt source,
# then install `msodbcsql17`. The `unixodbc-dev` package provides headers
# pyodbc links against.
USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl \
        gnupg \
        apt-transport-https \
        ca-certificates \
    && curl -sSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg \
    && curl -sSL https://packages.microsoft.com/config/debian/12/prod.list \
        > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends \
        msodbcsql17 \
        unixodbc-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# Python packages (airflow user -- never run pip as root in an Airflow image).
# -----------------------------------------------------------------------------
# We use a SEPARATE airflow/requirements-airflow.txt, not the project-root
# requirements.txt. Two reasons:
#
#   * The base Airflow image already installs pandas, SQLAlchemy, and so on.
#     We don't want pip to upgrade them past what Airflow has tested.
#   * The project-root requirements.txt has minimum-version pins
#     (e.g. sqlalchemy>=2.0.0) that conflict with Airflow's constraint pins
#     (SQLAlchemy 1.4.x for Airflow 2.10). pip errors out rather than
#     resolving the conflict, breaking the build.
#
# airflow/requirements-airflow.txt lists only the extras the extract script
# needs that aren't in the Airflow base image (pyodbc, python-dotenv,
# snowflake-connector-python[pandas]) with no version pins. The --constraint
# flag below points pip at Airflow's official tested-versions file, so the
# extras get installed at versions Airflow knows are compatible.
USER airflow

# Re-declare the same ARGs to inherit the values from the pre-FROM block.
# (Defaults are repeated for safety -- if someone strips the pre-FROM ARGs
# they still get sensible values here.)
ARG AIRFLOW_VERSION=2.10.3
ARG PYTHON_VERSION=3.11
ENV CONSTRAINTS_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"

COPY airflow/requirements-airflow.txt /tmp/requirements-airflow.txt
RUN pip install --no-cache-dir -r /tmp/requirements-airflow.txt --constraint "${CONSTRAINTS_URL}"
