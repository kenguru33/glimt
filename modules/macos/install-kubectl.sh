#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="kubectl"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"

deps() { log "No additional dependencies."; }

install() {
  if brew list kubectl &>/dev/null; then
    log "kubectl already installed."
  else
    brew install kubectl
  fi
  verify_binary kubectl version --client
}

config() {
  mkdir -p "$ZSH_CONFIG_DIR"
  deploy_config "$SCRIPT_DIR/config/kubectl.zsh" "$ZSH_CONFIG_DIR/kubectl.zsh"
}

clean() {
  brew uninstall kubectl 2>/dev/null || true
  rm -f "$ZSH_CONFIG_DIR/kubectl.zsh"
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
