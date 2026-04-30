# Secure-CI-template - Project README

Secure-CI-template is a **security pipeline lab** built around the same application workload as [AuthLab](https://github.com/tashauzzz/authlab).

Its role is to document **CI security verification**: how the safer application state is checked through a reproducible pipeline with source-code analysis, dependency auditing, SBOM generation, container image scanning, authenticated API DAST, and aggregated security reporting.

This project is the CI/security-verification layer of the wider portfolio:

* **[Project 1](https://github.com/tashauzzz/AuthLab):** application security behavior
* **[Project 2](https://github.com/tashauzzz/Secure-CI-template):** CI security verification around the same app
* **Project 3:** deployment hardening around the same app

---

## 1) Project scope

Secure-CI-template focuses on pipeline-level security verification:

* source-code checks,
* Python dependency auditing,
* dependency inventory generation,
* container image OS/base-image scanning,
* authenticated runtime API scanning,
* report artifact generation,
* security summary aggregation,
* documented green/red pipeline behavior.

The pipeline is designed to be reproducible both locally and in GitHub Actions. The repository focuses on how security checks are orchestrated, enforced, and reported around the application workload.

---

## 2) How to navigate this repo

### Documentation entry points

* **Security Policy — [security_policy.md](docs/security_policy.md)**

  Defines the current enforcement model: enabled checks, blocking conditions, non-blocking findings, report expectations, and reviewed suppressions.

* **Pipeline Overview — [pipeline_overview.md](docs/pipeline_overview.md)**

  Explains how the pipeline is organized: script map, execution profiles, supporting files, artifact flow, and GitHub Actions orchestration.

* **Red/Green Demo — [red_green_demo.md](docs/red_green_demo.md)**

  Shows representative successful and failing pipeline scenarios tied to the current security policy.