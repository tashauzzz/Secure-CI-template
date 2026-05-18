#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)/_common.sh"
umask 077

MODE="full"   # app | tools | full
SEEN_MODE=0
PY=""

VENV_DIR="$REPO_ROOT/.venv"
APP_REQ="$REPO_ROOT/requirements.txt"
TOOLS_REQ="$REPO_ROOT/requirements_dev.txt"

for arg in "$@"; do
  if [[ "$arg" == "app" || "$arg" == "tools" || "$arg" == "full" ]]; then
    if [[ "$SEEN_MODE" -eq 1 && "$MODE" != "$arg" ]]; then
      die "Conflicting modes: '$MODE' and '$arg' (use only one: app|tools|full)"
    fi
    MODE="$arg"
    SEEN_MODE=1
  else
    die "Unknown arg: $arg (use: [app|tools|full])"
  fi
done

info "Repo root: $REPO_ROOT"
info "Mode: $MODE"
info "Virtual env: $VENV_DIR"

ensure_host_venv() {
  if [[ -x "$VENV_DIR/bin/python" ]]; then
    info "Using existing .venv"
  else
    command -v python3 >/dev/null 2>&1 || die "python3 not found (required to create .venv)"
    info "Creating .venv"
    python3 -m venv "$VENV_DIR" || die "Failed to create .venv"
  fi

  PY="$VENV_DIR/bin/python"
  [[ -x "$PY" ]] || die "Python not found in .venv: $PY"

  info "Python selected: $PY"
  info "Python version: $("$PY" -V 2>&1)"

  info "Upgrading pip in .venv"
  "$PY" -m pip install --upgrade pip || die "Failed to upgrade pip in .venv"

  info "pip version: $("$PY" -m pip --version 2>&1)"
}

install_requirements_file() {
  local req_file="$1"
  [[ -s "$req_file" ]] || die "Requirements file missing or empty: $req_file"

  info "Installing $(basename "$req_file") into .venv"
  "$PY" -m pip install -r "$req_file" || die "Failed to install: $req_file"
}

ensure_host_venv

case "$MODE" in
  app)
    install_requirements_file "$APP_REQ"
    ;;
  tools)
    install_requirements_file "$TOOLS_REQ"
    ;;
  full)
    install_requirements_file "$APP_REQ"
    install_requirements_file "$TOOLS_REQ"
    ;;
  *)
    die "Unsupported mode: $MODE"
    ;;
esac

info "Host tools bootstrap complete (mode=$MODE)"
info "To activate .venv in current shell, run: source .venv/bin/activate"
exit 0