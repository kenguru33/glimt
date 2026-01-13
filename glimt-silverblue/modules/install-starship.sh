#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Starship install failed at line $LINENO" >&2' ERR

MODULE_NAME="starship"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

LOCAL_BIN="$HOME_DIR/.local/bin"
CONFIG_DIR="$HOME_DIR/.zsh/config"

# --------------------------------------------------
# Resolve repo root (modules/ -> repo/)
# --------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
MODULES_DIR="$(dirname "$SCRIPT_PATH")"
REPO_ROOT="$(dirname "$MODULES_DIR")"

TEMPLATE_FILE="$REPO_ROOT/config/starship.zsh"
TARGET_FILE="$CONFIG_DIR/starship.zsh"

log() { echo "[$MODULE_NAME] $*"; }

# --------------------------------------------------
# Step: deps
# --------------------------------------------------
deps() {
  log "Checking dependencies for Starship"
  command -v curl >/dev/null || {
    log "curl missing – installing"
    sudo dnf install -y curl
  }
}

# --------------------------------------------------
# Step: install
# --------------------------------------------------
install() {
  log "Installing Starship"

  mkdir -p "$LOCAL_BIN"

  if [[ ! -x "$LOCAL_BIN/starship" ]]; then
    curl -fsSL https://starship.rs/install.sh |
      sh -s -- -y --bin-dir "$LOCAL_BIN"

    chown "$REAL_USER:$REAL_USER" "$LOCAL_BIN/starship"
    log "Starship installed to $LOCAL_BIN"
  else
    log "Starship already installed"
  fi
}

# --------------------------------------------------
# Step: config
# --------------------------------------------------
config() {
  log "Installing starship.zsh config"

  [[ -f "$TEMPLATE_FILE" ]] || {
    echo "❌ Missing template: $TEMPLATE_FILE" >&2
    exit 1
  }

  mkdir -p "$CONFIG_DIR"
  cp "$TEMPLATE_FILE" "$TARGET_FILE"
  chown "$REAL_USER:$REAL_USER" "$TARGET_FILE"

  log "Installed $TARGET_FILE"
}

# --------------------------------------------------
# Step: clean
# --------------------------------------------------
clean() {
  log "Cleaning Starship setup"

  rm -f "$LOCAL_BIN/starship"
  rm -f "$TARGET_FILE"

  log "Clean complete"
}

# --------------------------------------------------
# Entry point
# --------------------------------------------------
case "$ACTION" in
all)
  deps
  install
  config
  ;;
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  echo "❌ Unknown action: $ACTION"
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac

exit 0
