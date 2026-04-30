#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/_common.sh"

PROFILE="dev"
SEEN_PROFILE=0

for arg in "$@"; do
  case "$arg" in
    dev|ci)
      if [[ "$SEEN_PROFILE" -eq 1 && "$PROFILE" != "$arg" ]]; then
        die "Conflicting profiles: '$PROFILE' and '$arg' (use only one: dev|ci)"
      fi
      PROFILE="$arg"
      SEEN_PROFILE=1
      ;;
    *)
      die "Unknown arg: $arg (use: [dev|ci])"
      ;;
  esac
done

ENV_FILE="$REPO_ROOT/.env"
if [[ "$PROFILE" == "ci" ]]; then
  ENV_FILE="$REPO_ROOT/.env.ci"
fi

[[ -f "$ENV_FILE" ]] || die "Missing env file: $ENV_FILE (run ./scripts/00_env_bootstrap.sh $PROFILE first)"

DB_INIT="$REPO_ROOT/scripts/db/db_init.py"
[[ -f "$DB_INIT" ]] || die "DB init script not found: $DB_INIT"

STATE_DIR="$REPO_ROOT/.state"
READY_FILE="$STATE_DIR/db-ready.$PROFILE"

if [[ -x "$REPO_ROOT/.venv/bin/python" ]]; then
  PY="$REPO_ROOT/.venv/bin/python"
else
  command -v python3 >/dev/null 2>&1 || die "python3 not found"
  PY="$(command -v python3)"
fi

info "Profile: $PROFILE"
info "Env file: $ENV_FILE"
info "Python: $PY"
info "DB init script: $DB_INIT"
info "Ready marker: $READY_FILE"

mkdir -p "$STATE_DIR"
rm -f "$READY_FILE"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

[[ -n "${DB_PATH:-}" ]] || die "DB_PATH is empty or missing after loading: $ENV_FILE"
info "DB_PATH=$DB_PATH"

info "Initializing database..."
"$PY" "$DB_INIT" init || die "DB init failed"

info "Verifying database..."
"$PY" "$DB_INIT" verify || die "DB verify failed"

cat > "$READY_FILE" <<EOF
PROFILE=$PROFILE
ENV_FILE=$ENV_FILE
DB_PATH=$DB_PATH
STATUS=ready
EOF

info "DB init + verify complete"
info "Ready marker written: $READY_FILE"
exit 0