#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/_common.sh"
umask 077

PROFILE="dev"   # dev | ci
FORCE=0
SEEN_PROFILE=0
PY=""

for arg in "$@"; do

  	if [[ "$arg" == "--force" ]]; then
    	FORCE=1
  	elif [[ "$arg" == "ci" || "$arg" == "dev" ]]; then
    	if [[ "$SEEN_PROFILE" -eq 1 && "$PROFILE" != "$arg" ]]; then
      	die "Conflicting profiles: '$PROFILE' and '$arg' (use only one: dev|ci)"
    	fi
    	PROFILE="$arg"
    	SEEN_PROFILE=1
    else
    	die "Unknown arg: $arg (use: [--force] [dev|ci])"
  	fi
done

# Pick template + output file
if [[ "$PROFILE" == "ci" ]]; then
	SRC="$REPO_ROOT/.env.ci.example"
	FINAL_DST="$REPO_ROOT/.env.ci"
else
	SRC="$REPO_ROOT/.env.example"
	FINAL_DST="$REPO_ROOT/.env"
fi

WORK_DST="${FINAL_DST}.tmp"
SKIP_ENV_WRITE=0

STATE_DIR="$REPO_ROOT/.state"
READY_FILE="$STATE_DIR/db-ready.$PROFILE"

cleanup_tmp() {
	local status=$?
	if [[ "$status" -ne 0 && -f "$WORK_DST" ]]; then
		rm -f "$WORK_DST" || true
		info "Removed incomplete temp file: $WORK_DST"
	fi
}

trap cleanup_tmp EXIT

info "Repo root: $REPO_ROOT"
info "Profile: $PROFILE"
info "Template: $SRC"
info "Output: $FINAL_DST"

# Refuse overwrite unless --force
if [[ -f "$FINAL_DST" && "$FORCE" -ne 1 ]]; then
	info "File already exists, not touching: $FINAL_DST (use --force to overwrite)"
	SKIP_ENV_WRITE=1
fi

[[ -f "$SRC" ]] || die "Template not found: $SRC"

# Helper: set KEY=VALUE in file (replace or append)
set_kv() {
	local file="$1" key="$2" val="$3"
	local tmp="${file}.tmp"

	awk -v k="$key" -v v="$val" '
		BEGIN { found=0 }
		$0 ~ ("^" k "=") { print k "=" v; found=1; next }
		{ print }
		END { if (found==0) print k "=" v }
	' "$file" > "$tmp" || return 1

	mv "$tmp" "$file" || return 1
	return 0
}

# Helper: read KEY value (best-effort)
get_kv() {
	local file="$1" key="$2"
	grep -E "^${key}=" "$file" 2>/dev/null | head -n 1 | cut -d= -f2-
}

rand_hex() {
	od -An -N "$1" -tx1 /dev/urandom | tr -d ' \n'
}

is_truthy() {
	local v
	v="$(printf "%s" "${1:-}" | tr '[:upper:]' '[:lower:]')"
	[[ "$v" == "true" || "$v" == "1" || "$v" == "yes" || "$v" == "on" ]]
}

MIN_ADMIN_PASS_LEN=12

password_is_forbidden() {
	local pwd="$1"
	local lowered

	lowered="$(printf "%s" "$pwd" | tr '[:upper:]' '[:lower:]')"

	case "$lowered" in
		admin|password|adminadmin|passwordpassword|qwerty|letmein|1|11111111|12345678|123456789|1234567890)
			return 0
			;;
		*)
			return 1
			;;
	esac
}

validate_admin_password() {
	local pwd="$1"

	[[ -n "$pwd" ]] || die "Admin password must not be empty"

	[[ -n "${pwd//[[:space:]]/}" ]] || die "Admin password must not be blank or whitespace-only"

	if [[ "${#pwd}" -lt "$MIN_ADMIN_PASS_LEN" ]]; then
		die "Admin password must be at least $MIN_ADMIN_PASS_LEN characters long"
	fi

	if password_is_forbidden "$pwd"; then
		die "Admin password is too weak or too common"
	fi
}

prompt_admin_password() {
	local pwd1="" pwd2=""

	while true; do
		read -r -s -p "Admin password (hidden): " pwd1
		printf "\n" >&2
		read -r -s -p "Repeat admin password: " pwd2
		printf "\n" >&2

		[[ "$pwd1" == "$pwd2" ]] || {
			printf "[ERROR] Passwords do not match. Try again.\n" >&2
			continue
		}

		validate_admin_password "$pwd1"
		printf "%s" "$pwd1"
		return 0
	done
}

require_kv_ready() {
	local file="$1" key="$2" val
	val="$(get_kv "$file" "$key")"

	[[ -n "${val// }" ]] || die "Required key '$key' is empty or missing in: $file"

	case "$val" in
		CHANGE_ME|*EXAMPLE*|*example*|*PLACEHOLDER*)
			die "Key '$key' still looks like a placeholder in: $file"
			;;
	esac
}

validate_final_env() {
	local file="$1"

	[[ -f "$file" ]] || die "Env file not found: $file"

	require_kv_ready "$file" "SECRET_KEY"
	require_kv_ready "$file" "DEV_API_KEY"
	require_kv_ready "$file" "DB_PATH"
	require_kv_ready "$file" "ADMIN_PWHASH"

	local mfa_enabled
	mfa_enabled="$(get_kv "$file" "ADMIN_MFA_ENABLED")"

	if is_truthy "$mfa_enabled"; then
		require_kv_ready "$file" "ADMIN_MFA_SECRET"
	fi
}

if [[ "$SKIP_ENV_WRITE" -eq 0 ]]; then
	mkdir -p "$STATE_DIR"
	rm -f "$READY_FILE"
	info "Cleared stale DB ready marker: $READY_FILE"

	# Copy template -> temp output
	cp -f "$SRC" "$WORK_DST" || die "Failed to copy template to temp file: $WORK_DST"
	info "Created temp file: $WORK_DST"

	# Normalize line endings + drop whitespace-only lines (env loader is strict)
	sed -i 's/\r$//' "$WORK_DST" 2>/dev/null || true
	sed -i '/^[[:space:]]*$/d' "$WORK_DST" 2>/dev/null || true

	# Tight permissions: env files contain secrets
	chmod 600 "$WORK_DST" 2>/dev/null || true

	# Generate cheap per-run values
	SECRET_KEY="$(rand_hex 32)"
	DEV_API_KEY="dev-$(rand_hex 12)"

	set_kv "$WORK_DST" "SECRET_KEY" "$SECRET_KEY" || die "Failed to set SECRET_KEY"
	set_kv "$WORK_DST" "DEV_API_KEY" "$DEV_API_KEY" || die "Failed to set DEV_API_KEY"
	info "Generated: SECRET_KEY, DEV_API_KEY"

	# ADMIN_PWHASH:
	# - dev: generate interactively
	# - ci: keep value from template
	if [[ "$PROFILE" == "dev" ]]; then

	info "Ensuring app host dependencies via 01_host_tools_bootstrap.sh app"
	"$REPO_ROOT/scripts/01_host_tools_bootstrap.sh" app || die "Host tools bootstrap failed (mode=app)"
	
	PY="$REPO_ROOT/.venv/bin/python"
	[[ -x "$PY" ]] || die "Python not found in .venv after app bootstrap: $PY"
	
	"$PY" -c 'import werkzeug.security' >/dev/null 2>&1 || die "Missing Python module: werkzeug"
	ADMIN_PASSWORD="$(prompt_admin_password)"

	ADMIN_PWHASH="$(
		ADMIN_PASSWORD="$ADMIN_PASSWORD" "$PY" -c '
from werkzeug.security import generate_password_hash
import os
print(generate_password_hash(os.environ["ADMIN_PASSWORD"], method="scrypt"))
'
	)"

	unset ADMIN_PASSWORD

	set_kv "$WORK_DST" "ADMIN_PWHASH" "'$ADMIN_PWHASH'" || die "Failed to set ADMIN_PWHASH"
	info "Generated: ADMIN_PWHASH"
	else
		require_kv_ready "$WORK_DST" "ADMIN_PWHASH"
		info "CI profile: keeping ADMIN_PWHASH from template"
	fi

	# MFA secret only if enabled
	MFA_ENABLED="$(get_kv "$WORK_DST" "ADMIN_MFA_ENABLED")"

	if is_truthy "$MFA_ENABLED"; then
		if [[ "$PROFILE" == "dev" ]]; then
			"$PY" -c 'import pyotp' >/dev/null 2>&1 || die "Missing Python module: pyotp"

			MFA_SECRET="$("$PY" -c 'import pyotp; print(pyotp.random_base32())')"
			set_kv "$WORK_DST" "ADMIN_MFA_SECRET" "$MFA_SECRET" || die "Failed to set ADMIN_MFA_SECRET"
			info "Generated: ADMIN_MFA_SECRET"
		else
			require_kv_ready "$WORK_DST" "ADMIN_MFA_SECRET"
			info "CI profile: keeping ADMIN_MFA_SECRET from template"
		fi
	else
		info "MFA disabled (ADMIN_MFA_ENABLED=$MFA_ENABLED) -> not generating ADMIN_MFA_SECRET"
	fi

	# Re-apply tight permissions after edits
	chmod 600 "$WORK_DST" 2>/dev/null || true
	mv -f "$WORK_DST" "$FINAL_DST" || die "Failed to move temp file into place: $FINAL_DST"
fi
validate_final_env "$FINAL_DST"
info "Validated env file: $FINAL_DST"

if [[ "$PROFILE" == "dev" ]]; then
	if [[ "$SKIP_ENV_WRITE" -eq 0 ]]; then
		info "Dev bootstrap complete"
	else
		info "Dev env file kept as-is"
	fi

	info "To activate .venv in current shell, run: source .venv/bin/activate"
else
	if [[ "$SKIP_ENV_WRITE" -eq 0 ]]; then
		info "CI bootstrap complete"
	else
		info "CI env file kept as-is"
	fi
fi

info "Done: $FINAL_DST"
exit 0