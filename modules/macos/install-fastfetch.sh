#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="fastfetch"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FASTFETCH_CONFIG_DIR="$HOME_DIR/.config/fastfetch"

deps() { log "No additional dependencies."; }

install() {
  if brew list fastfetch &>/dev/null; then
    log "fastfetch already installed."
  else
    brew install fastfetch
  fi
  verify_binary fastfetch --version
}

config() {
  mkdir -p "$FASTFETCH_CONFIG_DIR"
  deploy_config "$SCRIPT_DIR/config/fastfetch.jsonc" "$FASTFETCH_CONFIG_DIR/config.jsonc"
}

clean() {
  brew uninstall fastfetch 2>/dev/null || true
  rm -f "$FASTFETCH_CONFIG_DIR/config.jsonc"
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
