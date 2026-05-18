#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/_common.sh"

REPORT_DIR="$REPO_ROOT/reports"
PIP_AUDIT="$REPO_ROOT/.venv/bin/pip-audit"

APP_REQUIREMENTS="$REPO_ROOT/requirements.txt"
DEV_REQUIREMENTS="$REPO_ROOT/requirements_dev.txt"

APP_REPORT_FILE="$REPORT_DIR/pip-audit-app.json"
DEV_REPORT_FILE="$REPORT_DIR/pip-audit-dev.json"

info "Running pip-audit..."

# pip-audit must come from the project .venv
[[ -x "$PIP_AUDIT" ]] || die "pip-audit not found in .venv: $PIP_AUDIT
Install:
  ./.venv/bin/pip install -r requirements_dev.txt"

info "pip-audit binary: $PIP_AUDIT"
PIP_AUDIT_VER="$("$PIP_AUDIT" --version 2>/dev/null || true)"
[[ -n "$PIP_AUDIT_VER" ]] && info "$PIP_AUDIT_VER"

mkdir -p "$REPORT_DIR"
info "Reports dir: $REPORT_DIR"

run_pip_audit() {
  local label="$1"
  local requirements_file="$2"
  local report_file="$3"

  [[ -s "$requirements_file" ]] || die "$label requirements file missing or empty: $requirements_file"
  info "$label requirements file: $requirements_file"

  # pip-audit exit codes:
  #   0 -> no known vulnerabilities found
  #   1 -> vulnerabilities found
  #   other non-zero -> tool/runtime failure
  #
  # For this project:
  # - 0 and 1 are both valid scan outcomes
  # - only tool/runtime failure should fail the step
  set +e
  "$PIP_AUDIT" -r "$requirements_file" --format json -o "$report_file"
  local rc=$?
  set -e

  local norm
  if [[ "$rc" -eq 0 || "$rc" -eq 1 ]]; then
    norm=0
  else
    norm=2
  fi

  info "$label pip-audit exit=$rc (normalized to $norm)"

  if [[ "$norm" -eq 2 ]]; then
    die "$label pip-audit failed to run (exit=$rc). Check: venv install, requirements path."
  fi

  if [[ -s "$report_file" ]]; then
    info "$label report exists and is not empty"
    info "$label report size: $(wc -c < "$report_file") bytes"
  else
    die "$label report missing or empty: $report_file"
  fi
}

run_pip_audit "App" "$APP_REQUIREMENTS" "$APP_REPORT_FILE"
run_pip_audit "Dev" "$DEV_REQUIREMENTS" "$DEV_REPORT_FILE"

exit 0