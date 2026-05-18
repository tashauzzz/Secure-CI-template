#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/_common.sh"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found"
}

need_cmd docker
need_cmd python3

[[ "$#" -eq 0 ]] || die "This script is CI-only and does not accept arguments"

REPORT_DIR="$REPO_ROOT/reports"
REPORT_HTML_HOST="$REPORT_DIR/zap-api.html"
REPORT_JSON_HOST="$REPORT_DIR/zap-api.json"

ZAP_VERSION_FILE="$REPO_ROOT/security/zap/VERSION"


PLAN_HOST="$REPO_ROOT/security/zap/plan_auth_ci.yaml"
PLAN_CONT="/zap/wrk/security/zap/plan_auth_ci.yaml"

ENV_FILE="$REPO_ROOT/.env.ci"

[[ -f "$ENV_FILE" ]] || die "Env file not found: $ENV_FILE
Run setup first:
  ./scripts/00_env_bootstrap.sh ci"

ENV_FILE_NAME="$(basename "$ENV_FILE")"

DEV_API_KEY="$(bash -c 'set -a; source "$1"; printf "%s" "${DEV_API_KEY:-}"' _ "$ENV_FILE")"
[[ -n "$DEV_API_KEY" ]] || die "DEV_API_KEY is empty or missing in: $ENV_FILE"

PLAN_RENDERED_HOST="$REPO_ROOT/security/zap/plan_auth_ci.rendered.yaml"
PLAN_RENDERED_CONT="/zap/wrk/security/zap/plan_auth_ci.rendered.yaml"

trap '[[ -n "${PLAN_RENDERED_HOST:-}" && -f "${PLAN_RENDERED_HOST:-}" ]] && rm -f "$PLAN_RENDERED_HOST"' EXIT
command -v python3 >/dev/null 2>&1 || die "python3 not found"

python3 - "$PLAN_HOST" "$PLAN_RENDERED_HOST" "$DEV_API_KEY" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1])
dst = Path(sys.argv[2])
key = sys.argv[3]

text = src.read_text(encoding="utf-8")
text = text.replace("__DEV_API_KEY__", key)
dst.write_text(text, encoding="utf-8")
PY

PLAN_HOST="$PLAN_RENDERED_HOST"
PLAN_CONT="$PLAN_RENDERED_CONT"

info "Running authenticated ZAP API scan (Automation Framework)..."

[[ -s "$ZAP_VERSION_FILE" ]] || die "ZAP version file missing or empty: $ZAP_VERSION_FILE"
ZAP_VERSION="$(tr -d ' \t\r\n' < "$ZAP_VERSION_FILE")"
[[ -n "$ZAP_VERSION" ]] || die "ZAP version is empty in: $ZAP_VERSION_FILE"

ZAP_IMG="ghcr.io/zaproxy/zaproxy:${ZAP_VERSION}"

[[ -s "$PLAN_HOST" ]] || die "Automation plan missing or empty: $PLAN_HOST"
info "automation plan: $PLAN_HOST"

info "Checking Docker availability..."
docker info >/dev/null 2>&1 || die "Docker is not running or available"


info "env file: $ENV_FILE"

# authlab must be running (compose service)
CID="$(AUTHLAB_ENV_FILE="$ENV_FILE_NAME" docker compose --env-file "$ENV_FILE" ps -q authlab)"
[[ -n "$CID" ]] || die "Service 'authlab' is not running. Start it first:
  ./scripts/00_env_bootstrap.sh ci
  ./scripts/02_app_db_init.sh ci
  ./scripts/03_image_build.sh
  ./scripts/04_runtime_up.sh"
info "container id: $CID"

NET="$(docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' "$CID" | head -n1)"
[[ -n "$NET" ]] || die "Could not detect Docker network for container: $CID"
info "compose network: $NET"

# preflight API health-check from inside the compose network (expect 401)
SMOKE_CODE="$(docker run --rm --network "$NET" curlimages/curl:8.6.0 \
  -sS -o /dev/null -w "%{http_code}" \
  http://authlab:5000/api/v1/auth/session || true)"
info "smoke check api: http=$SMOKE_CODE (expected 401)"

if [[ "$SMOKE_CODE" != "401" ]]; then
  die "API smoke-check failed (http=$SMOKE_CODE). Is authlab healthy? Check: AUTHLAB_ENV_FILE=$ENV_FILE_NAME docker compose --env-file $ENV_FILE logs --tail=200 authlab"
fi

mkdir -p "$REPORT_DIR"
info "Reports dir: $REPORT_DIR"

chmod 777 "$REPORT_DIR" || die "Failed to chmod reports dir: $REPORT_DIR"
info "Reports dir made writable for ZAP container"

rm -f "$REPORT_HTML_HOST" "$REPORT_JSON_HOST"
info "Removed old ZAP reports (if any)"

# Run ZAP Automation Framework plan
set +e
docker run --rm --network "$NET" \
  -v "$REPO_ROOT:/zap/wrk:rw" -w /zap/wrk \
  "$ZAP_IMG" \
  zap.sh -cmd -autorun "$PLAN_CONT"
RC=$?
set -e

info "ZAP exit=$RC"

if [[ "$RC" -ne 0 ]]; then
  die "ZAP Automation Framework run failed (exit=$RC). Check container output above."
fi

if [[ -s "$REPORT_HTML_HOST" && -s "$REPORT_JSON_HOST" ]]; then
  info "Reports exist and are not empty"
  info "HTML report size: $(wc -c < "$REPORT_HTML_HOST") bytes"
  info "JSON report size: $(wc -c < "$REPORT_JSON_HOST") bytes"
else
  die "HTML/JSON reports missing or empty: $REPORT_HTML_HOST, $REPORT_JSON_HOST"
fi

exit 0