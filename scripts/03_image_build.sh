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

[[ "$#" -eq 0 ]] || die "This script is CI-only and does not accept arguments"

ENV_FILE=".env.ci"

[[ -f "$ENV_FILE" ]] || die "Missing $ENV_FILE (run ./scripts/00_env_bootstrap.sh ci first)"

info "Using CI env: $ENV_FILE"
export AUTHLAB_ENV_FILE="$ENV_FILE"
info "AUTHLAB_ENV_FILE=$AUTHLAB_ENV_FILE"

APP_IMAGE="${AUTHLAB_IMAGE_REF:-authlab:baseline}"

info "Building image: $APP_IMAGE"
docker compose --env-file /dev/null build authlab || die "docker compose build failed"

if docker image inspect "$APP_IMAGE" >/dev/null 2>&1; then
	info "Image ready: $APP_IMAGE"
else
	die "Build completed but target image not found locally: $APP_IMAGE"
fi

exit 0