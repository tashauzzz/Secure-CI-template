#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/_common.sh"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found"
}

need_cmd docker
need_cmd jq

[[ "$#" -eq 0 ]] || die "This script is CI-only and does not accept arguments"

REPORT_DIR="$REPO_ROOT/reports"
REPORT_FILE_HOST="$REPORT_DIR/trivy-image.json"
REPORT_FILE_CONT="/work/reports/trivy-image.json"

TRIVY_VERSION_FILE="$REPO_ROOT/security/trivy/VERSION"
CACHE_HOST="$REPO_ROOT/.cache/trivy"
CACHE_CONT="/cache/trivy"

# target image (compose sets: image: authlab:baseline)
APP_IMAGE="${AUTHLAB_IMAGE_REF:-authlab:baseline}"

# default ownership: OS/base-image layer
TRIVY_IMAGE_PKG_TYPES="${TRIVY_IMAGE_PKG_TYPES:-os}"

# enabled by default: fail if scanned OS/base layer is EOL
TRIVY_IMAGE_EOL_EXIT_CODE="${TRIVY_IMAGE_EOL_EXIT_CODE:-30}"

info "Running Trivy image..."
info "Target image: $APP_IMAGE"
info "Package scope: $TRIVY_IMAGE_PKG_TYPES"
info "EOL gate exit code: $TRIVY_IMAGE_EOL_EXIT_CODE"

[[ -s "$TRIVY_VERSION_FILE" ]] || die "Trivy version file missing or empty: $TRIVY_VERSION_FILE"

TRIVY_VERSION="$(tr -d ' \t\r\n' < "$TRIVY_VERSION_FILE")"
[[ -n "$TRIVY_VERSION" ]] || die "Trivy version is empty in: $TRIVY_VERSION_FILE"

TRIVY_IMG="ghcr.io/aquasecurity/trivy:${TRIVY_VERSION}"
info "Trivy runner image: $TRIVY_IMG"

if ! docker image inspect "$APP_IMAGE" >/dev/null 2>&1; then
  die "Target image not found locally: $APP_IMAGE
Build it first:
  ./scripts/03_image_build.sh"
fi

mkdir -p "$REPORT_DIR" "$CACHE_HOST"
info "Reports dir: $REPORT_DIR"
info "Cache dir: $CACHE_HOST"

TRIVY_VER_OUT="$(docker run --rm "$TRIVY_IMG" --version 2>/dev/null || true)"
[[ -n "$TRIVY_VER_OUT" ]] && info "$TRIVY_VER_OUT"

run_trivy_image() {
  docker run --rm \
    -v "$REPO_ROOT:/work" -w /work \
    -v "$CACHE_HOST:$CACHE_CONT" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    "$TRIVY_IMG" \
    --cache-dir "$CACHE_CONT" \
    image \
    --scanners vuln \
    --pkg-types "$TRIVY_IMAGE_PKG_TYPES" \
    --no-progress \
    "$@"
}

count_total_by_severity() {
  local severity="$1"
  jq -r --arg sev "$severity" '
    [.Results[]? | (.Vulnerabilities // [])[] | select(.Severity == $sev)] | length
  ' "$REPORT_FILE_HOST"
}

count_fixable_by_severity() {
  local severity="$1"
  jq -r --arg sev "$severity" '
    [.Results[]?
     | (.Vulnerabilities // [])[]
     | select(.Severity == $sev and (.FixedVersion // "") != "")
    ] | length
  ' "$REPORT_FILE_HOST"
}

#
# 1) main scan: always generate a full JSON report, never fail on findings here
#
set +e
run_trivy_image \
  --format json \
  --output "$REPORT_FILE_CONT" \
  --exit-code 0 \
  "$APP_IMAGE"
RC=$?
set -e

info "trivy full scan exit=$RC"
if [[ "$RC" -ne 0 ]]; then
  die "Trivy full image scan failed (exit=$RC).
Check docker socket access, image name, cache mount, and network."
fi

if [[ -s "$REPORT_FILE_HOST" ]]; then
  info "Report exists and is not empty"
  info "Report size: $(wc -c < "$REPORT_FILE_HOST") bytes"
else
  die "Report missing or empty: $REPORT_FILE_HOST"
fi

#
# 2) EOL gate
#
if [[ "$TRIVY_IMAGE_EOL_EXIT_CODE" != "0" ]]; then
  info "Running EOL gate..."

  set +e
  run_trivy_image \
    --exit-code 0 \
    --exit-on-eol "$TRIVY_IMAGE_EOL_EXIT_CODE" \
    "$APP_IMAGE" >/dev/null
  RC=$?
  set -e

  if [[ "$RC" -eq "$TRIVY_IMAGE_EOL_EXIT_CODE" ]]; then
    die "Trivy gate failed: target image OS/base layer is end-of-life (EOL)."
  elif [[ "$RC" -ne 0 ]]; then
    die "Trivy EOL check failed unexpectedly (exit=$RC)."
  fi

  info "EOL gate passed"
else
  info "EOL gate disabled"
fi

#
# 3) summary from the full JSON
#
TOTAL_CRITICAL="$(count_total_by_severity CRITICAL)"
TOTAL_HIGH="$(count_total_by_severity HIGH)"
TOTAL_MEDIUM="$(count_total_by_severity MEDIUM)"
TOTAL_LOW="$(count_total_by_severity LOW)"
TOTAL_UNKNOWN="$(count_total_by_severity UNKNOWN)"

FIXABLE_CRITICAL="$(count_fixable_by_severity CRITICAL)"
FIXABLE_HIGH="$(count_fixable_by_severity HIGH)"
FIXABLE_MEDIUM="$(count_fixable_by_severity MEDIUM)"
FIXABLE_LOW="$(count_fixable_by_severity LOW)"
FIXABLE_UNKNOWN="$(count_fixable_by_severity UNKNOWN)"

UNFIXED_CRITICAL="$((TOTAL_CRITICAL - FIXABLE_CRITICAL))"
UNFIXED_HIGH="$((TOTAL_HIGH - FIXABLE_HIGH))"
UNFIXED_MEDIUM="$((TOTAL_MEDIUM - FIXABLE_MEDIUM))"
UNFIXED_LOW="$((TOTAL_LOW - FIXABLE_LOW))"
UNFIXED_UNKNOWN="$((TOTAL_UNKNOWN - FIXABLE_UNKNOWN))"

info "Trivy image summary:"
info "  CRITICAL: total=$TOTAL_CRITICAL fixable=$FIXABLE_CRITICAL unfixed=$UNFIXED_CRITICAL"
info "  HIGH:     total=$TOTAL_HIGH fixable=$FIXABLE_HIGH unfixed=$UNFIXED_HIGH"
info "  MEDIUM:   total=$TOTAL_MEDIUM fixable=$FIXABLE_MEDIUM unfixed=$UNFIXED_MEDIUM"
info "  LOW:      total=$TOTAL_LOW fixable=$FIXABLE_LOW unfixed=$UNFIXED_LOW"
info "  UNKNOWN:  total=$TOTAL_UNKNOWN fixable=$FIXABLE_UNKNOWN unfixed=$UNFIXED_UNKNOWN"

#
# 4) minimal vulnerability gate: fail only on fixable CRITICAL
#
if [[ "$FIXABLE_CRITICAL" -gt 0 ]]; then
  die "Trivy gate failed: fixable CRITICAL vulnerabilities detected in package scope '$TRIVY_IMAGE_PKG_TYPES' (count=$FIXABLE_CRITICAL)."
fi

info "Fixable CRITICAL gate passed"
exit 0