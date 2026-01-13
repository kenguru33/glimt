#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Volta setup failed at line $LINENO" >&2' ERR

MODULE_NAME="volta"
ACTION="${1:-all}"

# --------------------------------------------------
# Resolve real user (IMPORTANT)
# --------------------------------------------------
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

# --------------------------------------------------
# Resolve repo root (modules/ → repo/)
# --------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
MODULES_DIR="$(dirname "$SCRIPT_PATH")"
REPO_ROOT="$(dirname "$MODULES_DIR")"

CONFIG_DIR="$HOME_DIR/.zsh/config"
TEMPLATE_FILE="$REPO_ROOT/config/volta.zsh"
TARGET_FILE="$CONFIG_DIR/volta.zsh"

VOLTA_HOME="$HOME_DIR/.volta"
VOLTA_BIN="$VOLTA_HOME/bin/volta"
VOLTA_ENV="VOLTA_HOME=$VOLTA_HOME PATH=$VOLTA_HOME/bin:\$PATH"

log() { echo "[$MODULE_NAME] $*"; }

require_user() {
  if [[ "$EUID" -eq 0 ]]; then
    echo "❌ Do not run this module as root." >&2
    exit 1
  fi
}

# --------------------------------------------------
# deps
# --------------------------------------------------
deps() {
  log "Checking dependencies"
  command -v curl >/dev/null || {
    echo "❌ curl is required (install via rpm-ostree)" >&2
    exit 1
  }
}

# --------------------------------------------------
# install
# --------------------------------------------------
install() {
  require_user

  log "Installing Volta"

  if [[ ! -x "$VOLTA_BIN" ]]; then
    curl -fsSL https://get.volta.sh | bash -s -- --skip-setup
    log "Volta installed to $VOLTA_HOME"
  else
    log "Volta already installed"
  fi

  log "Ensuring Node.js via Volta"
  env $VOLTA_ENV "$VOLTA_BIN" install node
}

# --------------------------------------------------
# config
# --------------------------------------------------
config() {
  require_user

  log "Installing volta.zsh config"

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
# clean
# --------------------------------------------------
clean() {
  require_user

  log "Cleaning Volta setup"

  rm -rf "$VOLTA_HOME"
  rm -f "$TARGET_FILE"

  log "Clean complete"
}

# --------------------------------------------------
# entry point
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
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac

exit 0
