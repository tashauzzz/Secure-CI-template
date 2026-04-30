# Pipline overview

## 1. Purpose

This document provides a concise execution-oriented overview of the repository security pipeline.

It focuses on:

- script responsibilities
- supporting files that affect pipeline execution
- execution profiles (`dev` and `ci`)
- the relationship between local runs and GitHub Actions orchestration

---

## 2. Script map

### 2.1 Environment, database bootstrap, build, and runtime control

These scripts prepare and control the execution context used by later security stages.

- [00_env_bootstrap.sh](../scripts/00_env_bootstrap.sh) — selects the execution profile (`dev` or `ci`), prepares the effective environment file, and generates required runtime secrets/config values; with `--force`, rebuilds the target env file and regenerates local secrets for that profile
- [01_host_tools_bootstrap.sh](../scripts/01_host_tools_bootstrap.sh) — prepares the host-side Python virtual environment and installs either application dependencies (`app`), tooling dependencies (`tools`), or both (`full`)
- [02_app_db_init.sh](../scripts/02_app_db_init.sh) — initializes and verifies the application database for the selected profile
- [03_image_build.sh](../scripts/03_image_build.sh) — builds the application container image used by later image-security and runtime stages
- [04_runtime_up.sh](../scripts/04_runtime_up.sh) — starts the application runtime from an already built image and waits until the web and API endpoints are ready
- [99_down.sh](../scripts/99_down.sh) — stops and removes the runtime environment after execution

### 2.2 Static analysis and dependency inventory

These scripts run source-level and dependency-level security stages that do not require the application runtime.

- [05_sast_bandit.sh](../scripts/05_sast_bandit.sh) — runs Bandit against the Python codebase and writes `reports/bandit.json`
- [06_sca_pip_audit.sh](../scripts/06_sca_pip_audit.sh) — audits Python application and tooling dependencies for known vulnerabilities and writes `reports/pip-audit-app.json` and `reports/pip-audit-dev.json`
- [07_sbom_cyclonedx.sh](../scripts/07_sbom_cyclonedx.sh) — generates a CycloneDX SBOM from the Python dependency set and writes `reports/sbom.cdx.json`

### 2.3 Image security

This stage evaluates the built container image at the OS/base-image layer.

- [08_image_trivy_os.sh](../scripts/08_image_trivy_os.sh) — runs Trivy against the already built application image, writes `reports/trivy-image.json`, enforces an OS/base-image EOL gate, and fails on fixable CRITICAL vulnerabilities

### 2.4 Runtime API security

This stage evaluates the live application runtime after the service is already up.

- [09_dast_zap_api.sh](../scripts/09_dast_zap_api.sh) — runs an authenticated OWASP ZAP API scan against the running application, renders the automation plan with the active `DEV_API_KEY`, and writes `reports/zap-api.html` and `reports/zap-api.json`

### 2.5 Reporting and result aggregation

This stage consolidates outputs from earlier security stages into a reviewer-friendly summary artifact.

- [10_security_summary.sh](../scripts/10_security_summary.sh) — reads generated security reports, extracts key metrics, and writes `reports/security-summary.md`

When the workflow is configured to run the summary stage after upstream failures, the generated summary may be partial and may contain `N/A` values for reports that were not produced.

---

## 3. Supporting files and configuration

Some pipeline stages rely on supporting files that are not treated as standalone pipeline stages.

Key supporting files include:

- [.github/workflows/security.yaml](../.github/workflows/security.yaml) — defines GitHub Actions job orchestration, stage ordering, and artifact handoff between jobs
- [.github/dependabot.yml](../.github/dependabot.yml) — defines automated dependency update proposals for GitHub Actions and helps keep pinned workflow components current
- [dockerfile](../dockerfile) — defines the application image used by build, image-security, and runtime stages
- [docker-compose.yaml](../docker-compose.yaml) — defines the container runtime used by CI-oriented container execution
- [.env.example](../.env.example) and [.env.ci.example](../.env.ci.example) — provide profile templates used by environment bootstrap
- [requirements.txt](../requirements.txt) and [requirements_dev.txt](../requirement_dev.txt) — define application and tooling dependency sets used by host bootstrap modes
- [openapi.yaml](./openapi.yaml) — defines the API surface used by the ZAP OpenAPI-driven runtime scan
- [security/bandit/config.yaml](../security/bandit/config.yaml) — defines Bandit scan configuration
- [security/trivy/VERSION](../security/trivy/VERSION) — pins the Trivy runner image version
- [security/zap/VERSION](../security/zap/VERSION) — pins the ZAP runner image version
- [security/zap/plan_auth_ci.yaml](../security/zap/plan_auth_ci.yaml) — defines the authenticated ZAP Automation Framework plan
- [security/zap/scripts/authlab_session.js](../security/zap/scripts/authlab_session.js) — propagates authenticated session and CSRF state during the ZAP scan
- [scripts/_common.sh](../scripts/_common.sh) — provides shared shell helpers reused by stage scripts
- [scripts/db/db_init.py](../scripts/db/db_init.py) — implements database initialization and verification logic used by database bootstrap
- `.state/` — stores local database-ready markers produced by database bootstrap steps
- `data/` — stores the local SQLite database files used by the `dev` and `ci` profiles

---

## 4. Execution profiles

The repository uses two execution profiles:

- `ci`
- `dev`

The `ci` profile is the pipeline-shaped execution mode.
It is used in GitHub Actions and can also be selected locally when the goal is to reproduce CI behavior as closely as possible before pushing changes.

The `dev` profile is intended for local debugging and development-oriented execution.

Both profiles can exist locally at the same time.

### 4.1 Local profile entry points

Local runs typically begin with:

- `00_env_bootstrap.sh dev|ci`
- `01_host_tools_bootstrap.sh`
- `02_app_db_init.sh dev|ci`

`00_env_bootstrap.sh` selects the profile and creates the effective environment file from the matching template:

- `.env.example` -> `.env`
- `.env.ci.example` -> `.env.ci`

For local `dev` execution, `00_env_bootstrap.sh dev` already ensures the application-oriented host bootstrap path through `01_host_tools_bootstrap.sh app`.

For local `ci` execution, `00_env_bootstrap.sh ci` prepares the CI-shaped environment, but the host bootstrap path is still expected to be invoked explicitly as `01_host_tools_bootstrap.sh full`.

If the local `ci` run continues into image-based or runtime-oriented stages, it then proceeds through `03_image_build.sh` and `04_runtime_up.sh`, and is cleaned up with `99_down.sh`.

### 4.2 Profile-aware database state

`02_app_db_init.sh` accepts both `dev` and `ci`.

It expects the corresponding profile environment file to already exist:

- `.env` for `dev`
- `.env.ci` for `ci`

After successful initialization and verification, `02_app_db_init.sh` writes a profile-specific ready marker under `.state/`:

- `.state/db-ready.dev`
- `.state/db-ready.ci`

This marker records that database preparation completed successfully for the selected profile.

For `ci`, the ready marker is used by later runtime-oriented execution, including `04_runtime_up.sh`.

For `dev`, it mainly serves as local confirmation that database bootstrap completed successfully for that profile. After that, the application can be started directly with `python3 app.py`.  

For `ci`, direct local application startup is also technically possible once the corresponding environment and host dependencies are prepared, but the canonical `ci` path in this repository remains the pipeline-shaped flow.

---

## 5. GitHub Actions execution

A practical difference from the typical local `ci` path is `01_host_tools_bootstrap.sh`:
local `ci` runs usually use `full`, while the workflow uses `tools` only in the jobs that need host-side tooling.

This difference exists because local `ci` runs are typically used as end-to-end reproduction paths on a single host environment, while GitHub Actions scopes host bootstrap to the needs of each job.


