#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="volta"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VOLTA_HOME="$HOME_DIR/.volta"

deps() { log "No additional dependencies."; }

install() {
  if [[ -x "$VOLTA_HOME/bin/volta" ]]; then
    log "Volta already installed."
    return 0
  fi
  log "Installing Volta..."
  # --skip-setup avoids modifying shell profile (we deploy volta.zsh ourselves)
  curl -fsSL https://get.volta.sh | bash -s -- --skip-setup
  export PATH="$VOLTA_HOME/bin:$PATH"
  verify_binary volta --version
}

config() {
  log "Deploying volta.zsh config..."
  mkdir -p "$CONFIG_DIR"
  deploy_config "$SCRIPT_DIR/config/volta.zsh" "$CONFIG_DIR/volta.zsh"
}

clean() {
  rm -rf "$VOLTA_HOME"
  rm -f "$CONFIG_DIR/volta.zsh"
}

case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
