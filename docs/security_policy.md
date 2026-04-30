# Security Policy

## 1. Purpose / Scope

This policy defines the current security enforcement model for the repository CI pipeline.

It covers:

* Python source code checks
* Python dependency checks
* dependency inventory generation
* container image OS/base-image checks
* authenticated runtime API scanning.

---

## 2. Jobs

### `static`

Runs source-code and dependency-layer checks:

* Bandit
* pip-audit
* CycloneDX SBOM

### `image-security`

Builds the application image and scans the OS/base-image layer with Trivy.

### `runtime-zap`

Loads the built image, starts the runtime, and runs authenticated ZAP API scanning.

### `summary`

Aggregates available generated reports into a single markdown security summary artifact.

This job may still run after an upstream stage failure and produce a partial summary when some reports are unavailable.

### `runtime-nightly`

Runs scheduled drift-oriented checks:

* pip-audit
* Trivy image
* ZAP API
* nightly summary artifact

---

## 3. Tools and current role

| Tool             | Layer                                        | Current mode            | Artifact                                       |
| ---------------- | -------------------------------------------- | ----------------------- | ---------------------------------------------- |
| Bandit           | Python source code                           | Blocking                | `reports/bandit.json`                          |
| pip-audit        | Python application and tooling dependencies  | Signal-only on findings | `reports/pip-audit-app.json`, `reports/pip-audit-dev.json` |
| CycloneDX SBOM   | Dependency inventory / supply-chain evidence | Artifact-only           | `reports/sbom.cdx.json`                        |
| Trivy image      | Container OS/base-image layer                | Selective gate          | `reports/trivy-image.json`                     |
| ZAP API          | Authenticated runtime API surface            | Selective gate          | `reports/zap-api.html`, `reports/zap-api.json` |
| Security summary | Aggregated report / partial summary                           | Artifact-only           | `reports/security-summary.md`                  |

---

## 4. Blocking conditions

The pipeline blocks on:

* tool/runtime failure for any enabled check
* missing or empty required report artifact for an enabled report-producing security step
* Bandit findings that are not explicitly reviewed and suppressed
* Trivy image OS/base-image **EOL**
* Trivy image **fixable CRITICAL** OS/base-image findings
* ZAP API findings at **High** severity according to the ZAP Automation Framework plan

## 4.1 Repository-level enforcement

The blocking conditions above describe CI job outcomes: a stage fails the workflow when its configured gate is violated or when required reports cannot be produced.

The repository enforces these outcomes through GitHub branch protection / rulesets. The `main` branch requires the selected GitHub Actions checks to pass before merge.

---

## 5. Non-blocking findings

The following findings are currently recorded for review but do not block the pipeline:

* pip-audit application and tooling dependency findings
* Trivy image findings below the configured blocking threshold
* ZAP API findings below **High** severity

---

## 6. Reviewed suppressions

Current active reviewed suppressions are limited to **Bandit `B608`** cases.

These suppressions are used only for:

* intentional lab-only SQLi PoC code paths
* reviewed false positives where query fragments are fixed/allowlisted and user values remain parameterized

Suppressions are allowed only when they are narrow, reviewed, and documented inline.

### Known upstream-constrained dev-tooling advisory

Current known non-blocking dev-tooling advisory:

* `GHSA-vfmq-68hx-4jfw` for transitive `lxml` in the CycloneDX SBOM tooling chain.

This finding affects the dev/tooling dependency layer, not the application runtime dependency set. The fixed `lxml` version is `6.1.0`, while the current SBOM tooling dependency chain constrains `lxml` below version 6. The finding remains visible in the security summary and should be removed once the upstream SBOM tooling supports the fixed `lxml` release.