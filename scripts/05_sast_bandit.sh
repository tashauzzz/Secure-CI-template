#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/_common.sh"

REPORT_DIR="$REPO_ROOT/reports"
REPORT_FILE="$REPORT_DIR/bandit.json"
CFG="$REPO_ROOT/security/bandit/config.yaml"

info "Running Bandit…"

[[ -f "$CFG" ]] || die "Missing Bandit config: $CFG"
info "Bandit config: $CFG"

# Bandit must be from .venv
BANDIT="$REPO_ROOT/.venv/bin/bandit"
[[ -x "$BANDIT" ]] || die "Bandit not found in .venv: $BANDIT
Install:
  ./.venv/bin/pip install -r requirements_dev.txt"

info "Bandit: $BANDIT"
BANDIT_VER="$("$BANDIT" --version 2>/dev/null || true)"
[[ -n "$BANDIT_VER" ]] && info "$BANDIT_VER"

[[ -d "$REPO_ROOT/authlab" ]] || die "Missing target dir: $REPO_ROOT/authlab"
[[ -f "$REPO_ROOT/app.py" ]]  || die "Missing target file: $REPO_ROOT/app.py"

mkdir -p "$REPORT_DIR"
info "Reports dir: $REPORT_DIR"

# Run Bandit
set +e
"$BANDIT" -c "$CFG" -r authlab app.py -f json -o "$REPORT_FILE"
RC=$?
set -e

info "bandit exit=$RC"

if [[ "$RC" -ne 0 ]]; then
  die "Bandit reported findings or failed to run (exit=$RC). Review bandit.json and suppress only explicitly justified cases."
fi

if [[ -s "$REPORT_FILE" ]]; then
  info "Report exists and is not empty."
  info "Report size: $(wc -c < "$REPORT_FILE") bytes"
else
  die "Report missing or empty: $REPORT_FILE"
fi

exit 0
