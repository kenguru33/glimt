#!/bin/bash
set -euo pipefail
trap 'echo "❌ An error occurred at: $BASH_COMMAND" >&2' ERR

# === Config ===
SCRIPT_NAME="glimt"
REPO_DIR="${REPO_DIR:-$HOME/.glimt}"
EXTRA_SCRIPT="$REPO_DIR/setup-extras.sh"
SETUP_SCRIPT="$REPO_DIR/setup.sh"
LOCK_FILE="/tmp/.glimt.lock"
VALID_ACTIONS=("update" "module-selection")

# === Helpers ===
print_usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <action> [args...]

Actions:
  update             → git pull in ~/.glimt and re-run full setup.sh
  module-selection   → run setup-extras.sh (optional modules)

Any extra [args...] after the action are forwarded to the underlying script.
EOF
}

acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    echo "🔒 Glimt is already running (lock file exists: $LOCK_FILE)"
    echo "If this is an error, delete the lock file and retry:"
    echo "  rm -f $LOCK_FILE"
    exit 1
  fi
  echo "$$" >"$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT
}

ensure_repo() {
  if [[ ! -d "$REPO_DIR" ]]; then
    echo "❌ Repo directory not found: $REPO_DIR"
    echo "   Clone your repo there, e.g.:"
    echo "   git clone <url> \"$REPO_DIR\""
    exit 1
  fi
}

# === Actions ===
run_update() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  echo "🔄 Updating repository in $REPO_DIR..."
  git -C "$REPO_DIR" fetch --all --prune
  git -C "$REPO_DIR" pull --rebase --stat

  echo "🚀 Running full setup..."
  if [[ -x "$SETUP_SCRIPT" ]]; then
    (cd "$REPO_DIR" && exec bash "$SETUP_SCRIPT" "$@")
  else
    echo "❌ $SETUP_SCRIPT not found or not executable."
    exit 1
  fi
}

run_module_selection() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  echo "🎛️ Running module selection..."
  if [[ -x "$EXTRA_SCRIPT" ]]; then
    (cd "$REPO_DIR" && exec bash "$EXTRA_SCRIPT" "$@")
  else
    echo "❌ Missing or non-executable: $EXTRA_SCRIPT"
    exit 1
  fi
}

# === Entry Point ===
ACTION="${1:-}"
shift || true # forward any extra args to the called script

case "$ACTION" in
update)
  run_update "$@"
  ;;
module-selection)
  run_module_selection "$@"
  ;;
*)
  print_usage
  exit 1
  ;;
esac
