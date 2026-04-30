#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/_common.sh"

REPORT_DIR="$REPO_ROOT/reports"
REPORT_FILE="$REPORT_DIR/sbom.cdx.json"
CDX="$REPO_ROOT/.venv/bin/cyclonedx-py"
REQUIREMENTS="$REPO_ROOT/requirements.txt"

info "Generating CycloneDX SBOM"

# cyclonedx-py must be from .venv
[[ -x "$CDX" ]] || die "cyclonedx-py not found in .venv: $CDX
Install:
  ./.venv/bin/pip install -r requirements_dev.txt"

info "cyclonedx-py: $CDX"
CDX_VER="$("$CDX" --version 2>/dev/null || true)"
[[ -n "$CDX_VER" ]] && info "$CDX_VER"

# requirements must exist and not be empty
[[ -s "$REQUIREMENTS" ]] || die "requirements.txt missing or empty: $REQUIREMENTS"
info "Requirements: $REQUIREMENTS"

mkdir -p "$REPORT_DIR"
info "Reports dir: $REPORT_DIR"

# Run cyclonedx-py
set +e
"$CDX" requirements --of JSON --output-reproducible -o "$REPORT_FILE" "$REQUIREMENTS"
RC=$?
set -e

info "cyclonedx-py exit=$RC"

if [[ "$RC" -ne 0 ]]; then
  die "cyclonedx-py failed to run (exit=$RC). Check: venv install, requirements path"
fi

if [[ -s "$REPORT_FILE" ]]; then
  info "Report exists and is not empty"
  info "Report size: $(wc -c < "$REPORT_FILE") bytes"
else
  die "Report missing or empty: $REPORT_FILE"
fi

exit 0
