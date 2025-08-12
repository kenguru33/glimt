#!/bin/bash
set -e
trap 'echo "❌ An error occurred. Exiting." >&2' ERR

# === Config ===
SCRIPT_NAME="glimt"
REPO_DIR="$HOME/.glimt"
EXTRA_SCRIPT="$REPO_DIR/setup-extras.sh"
SETUP_SCRIPT="$REPO_DIR/setup.sh"
LOCK_FILE="/tmp/.glimt.lock"
VALID_ACTIONS=("update" "module-selection")

# === Functions ===

print_usage() {
  echo "Usage: $SCRIPT_NAME <action>"
  echo
  echo "Available actions:"
  echo "  update            → Pull latest changes from Git and re-run full setup"
  echo "  module-selection  → Run optional extras selector via setup-extra.sh"
  echo
}

acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    echo "🔒 Gimt is already running (lock file exists: $LOCK_FILE)"
    echo "If this is an error, delete the lock file manually and retry:"
    echo "  rm -f $LOCK_FILE"
    exit 1
  fi

  echo "$$" >"$LOCK_FILE"
  trap 'release_lock' EXIT
}

release_lock() {
  [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"
}

run_update() {
  acquire_lock

  echo "🔄 Updating repository..."
  git -C "$REPO_DIR" pull --rebase --stat

  echo "🚀 Running full setup..."
  if [[ -x "$SETUP_SCRIPT" ]]; then
    "$SETUP_SCRIPT"
  else
    echo "❌ $SETUP_SCRIPT not found or not executable."
    exit 1
  fi
}

run_module_selection() {
  if [[ -x "$EXTRA_SCRIPT" ]]; then
    echo "🎛️ Running module selection..."
    "$EXTRA_SCRIPT"
  else
    echo "❌ Missing or non-executable: $EXTRA_SCRIPT"
    exit 1
  fi
}

# === Entry Point ===
ACTION="${1:-}"

case "$ACTION" in
update)
  run_update
  ;;
module-selection)
  run_module_selection
  ;;
*)
  print_usage
  exit 1
  ;;
esac
