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

if [[ -f "$ENV_FILE" ]]; then
	info "Using CI env: $ENV_FILE"
else
	info "CI env file not found: $ENV_FILE (continuing with teardown)"
fi

export AUTHLAB_ENV_FILE="$ENV_FILE"
info "AUTHLAB_ENV_FILE=$AUTHLAB_ENV_FILE"

# stop + remove containers + network
docker compose --env-file /dev/null down --remove-orphans

info "Down: containers removed, network removed"
exit 0
