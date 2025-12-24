#!/bin/bash
set -euo pipefail
trap 'echo "❌ An error occurred at: $BASH_COMMAND" >&2' ERR

# === Config ===
SCRIPT_NAME="glimt"
REPO_DIR="${REPO_DIR:-$HOME/.glimt}"
EXTRA_SCRIPT="$REPO_DIR/setup-extras.sh"
SETUP_SCRIPT="$REPO_DIR/setup.sh"
LOCK_FILE="/tmp/.glimt.lock"
VALID_ACTIONS=("update" "module-selection" "install" "clean")

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
  OS_ID_LIKE="${ID_LIKE:-}"
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# Determine modules directory based on OS
if [[ "$OS_ID" == "fedora" || "$OS_ID_LIKE" == *"fedora"* || "$OS_ID" == "rhel" ]]; then
  MODULES_DIR="$REPO_DIR/modules/fedora"
elif [[ "$OS_ID" == "debian" || "$OS_ID_LIKE" == *"debian"* || "$OS_ID" == "ubuntu" ]]; then
  MODULES_DIR="$REPO_DIR/modules/debian"
else
  echo "❌ Unsupported OS: $OS_ID"
  echo "   Supported: Debian, Ubuntu, Fedora, RHEL"
  exit 1
fi

# === Helpers ===
print_usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <action> [args...]

Actions:
  update [module]     → git pull and run installers in modules/<os> with 'all', or only <module> if provided
  install <module>    → run modules/<os>/**/install-<module>.sh with 'all'
  clean <module>      → run modules/<os>/**/install-<module>.sh with 'clean'
  module-selection    → run setup-extras.sh (optional modules UI)

Note: <module> is the installer basename without "install-" and ".sh".
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

find_module_script() {
  local module="$1"
  find "$MODULES_DIR" -type f -name "install-$module.sh" -print -quit 2>/dev/null || true
}

run_installer() {
  local script="$1"
  local mode="$2"   # all | clean
  [[ -n "$script" && -f "$script" ]] || { echo "❌ Installer not found."; exit 1; }
  [[ -x "$script" ]] || { echo "ℹ️  Making installer executable: $script"; chmod +x "$script"; }
  echo "▶️  $(basename "$script") $mode"
  ( cd "$REPO_DIR" && bash "$script" "$mode" )
}

# === Actions ===
run_update() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  echo "🔄 Updating repository in $REPO_DIR..."
  git -C "$REPO_DIR" fetch --all --prune
  git -C "$REPO_DIR" pull --rebase --stat

  local maybe_module="${1:-}"
  if [[ -n "$maybe_module" ]]; then
    local script
    script="$(find_module_script "$maybe_module")"
    [[ -n "$script" ]] || { echo "❌ Module not found: $maybe_module"; exit 1; }
    run_installer "$script" "all"
  else
    echo "🚀 Running all installers in $MODULES_DIR with 'all'..."
    mapfile -t installers < <(find "$MODULES_DIR" -type f -name 'install-*.sh' -print 2>/dev/null | sort)
    if (( ${#installers[@]} == 0 )); then
      echo "ℹ️  No installers found under: $MODULES_DIR"
      return 0
    fi
    for script in "${installers[@]}"; do
      run_installer "$script" "all"
    done
  fi
}

run_install() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  local module="${1:-}"
  [[ -n "$module" ]] || { echo "Usage: $SCRIPT_NAME install <module>"; exit 2; }
  local script; script="$(find_module_script "$module")"
  [[ -n "$script" ]] || { echo "❌ Module not found: $module"; exit 1; }
  run_installer "$script" "all"
}

run_clean() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  local module="${1:-}"
  [[ -n "$module" ]] || { echo "Usage: $SCRIPT_NAME clean <module>"; exit 2; }
  local script; script="$(find_module_script "$module")"
  [[ -n "$script" ]] || { echo "❌ Module not found: $module"; exit 1; }
  run_installer "$script" "clean"
}

run_module_selection() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  echo "🎛️ Running module selection..."
  if [[ -x "$EXTRA_SCRIPT" ]]; then
    ( cd "$REPO_DIR" && bash "$EXTRA_SCRIPT" all )
  else
    echo "❌ Missing or non-executable: $EXTRA_SCRIPT"
    exit 1
  fi
}

# === Entry Point ===
ACTION="${1:-}"
shift || true

case "$ACTION" in
  update)            run_update "${1:-}" ;;
  install)           run_install "${1:-}" ;;
  clean)             run_clean "${1:-}" ;;
  module-selection)  run_module_selection ;;
  *)                 print_usage; exit 1 ;;
esac
