#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/_common.sh"

need_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "$1 not found"
}

# deps
need_cmd docker
docker compose version >/dev/null 2>&1 || die "docker compose not available"
need_cmd curl

[[ "$#" -eq 0 ]] || die "This script is CI-only and does not accept arguments"

ENV_FILE=".env.ci"
READY_FILE="$REPO_ROOT/.state/db-ready.ci"

[[ -f "$ENV_FILE" ]] || die "Missing $ENV_FILE
Run setup first:
  ./scripts/00_env_bootstrap.sh ci
  ./scripts/02_app_db_init.sh ci"

info "Using CI env: $ENV_FILE"
export AUTHLAB_ENV_FILE="$ENV_FILE"
info "AUTHLAB_ENV_FILE=$AUTHLAB_ENV_FILE"

[[ -f "$READY_FILE" ]] || die "Missing DB ready marker: $READY_FILE
Run setup first:
  ./scripts/00_env_bootstrap.sh ci
  ./scripts/02_app_db_init.sh ci"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

[[ -n "${DB_PATH:-}" ]] || die "DB_PATH is empty or missing in: $ENV_FILE"

DB_FILE="$DB_PATH"
if [[ "$DB_FILE" != /* ]]; then
	DB_FILE="$REPO_ROOT/$DB_FILE"
fi

[[ -s "$DB_FILE" ]] || die "Database file missing or empty: $DB_FILE
Run setup first:
  ./scripts/00_env_bootstrap.sh ci
  ./scripts/02_app_db_init.sh ci"

info "DB ready marker found: $READY_FILE"
info "Database file: $DB_FILE"

APP_IMAGE="${AUTHLAB_IMAGE_REF:-authlab:baseline}"

# runtime step must reuse an existing image, not build a new one
docker image inspect "$APP_IMAGE" >/dev/null 2>&1 || die \
  "Required image not found locally: $APP_IMAGE
Run build first:
  ./scripts/03_image_build.sh"

info "Starting service"
docker compose --env-file /dev/null up -d authlab || die "docker compose up failed"

# wait for readiness (WEB + API)
URL_WEB="http://127.0.0.1:5000/login"
URL_API="http://127.0.0.1:5000/api/v1/auth/session"

TRIES=60
SLEEP_SEC=0.25

WEB_CODE="000"
API_CODE="000"

for _ in $(seq 1 "$TRIES"); do
	WEB_CODE="$(curl -sS -o /dev/null -w "%{http_code}" "$URL_WEB" || true)"
	API_CODE="$(curl -sS -o /dev/null -w "%{http_code}" "$URL_API" || true)"

	if [[ "$WEB_CODE" == "200" && ( "$API_CODE" == "401" || "$API_CODE" == "409" ) ]]; then
		info "Ready:"
		info "  WEB: $URL_WEB (http=$WEB_CODE)"
		info "  API: $URL_API (http=$API_CODE)"
		exit 0
	fi

	sleep "$SLEEP_SEC"
done

die "Not ready after ${TRIES} tries:
  WEB: $URL_WEB (last_http=$WEB_CODE, expected 200)
  API: $URL_API (last_http=$API_CODE, expected 401 or 409)
Verify setup order:
  ./scripts/00_env_bootstrap.sh ci
  ./scripts/02_app_db_init.sh ci
  ./scripts/03_image_build.sh
Check logs:
  docker compose logs --tail=200 authlab"