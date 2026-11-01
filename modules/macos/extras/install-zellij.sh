#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="zellij"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ZELLIJ_CONFIG_DIR="$HOME_DIR/.config/zellij"
ZELLIJ_CONFIG_FILE="$ZELLIJ_CONFIG_DIR/config.kdl"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KDL_TEMPLATE="$SCRIPT_DIR/../config/zellij.kdl"

macos_guard() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
}

deps() { log "No additional dependencies."; }

install() {
  brew_ensure zellij
  verify_binary zellij --version
}

config() {
  log "Configuring Zellij..."
  mkdir -p "$ZELLIJ_CONFIG_DIR"
  deploy_config "$KDL_TEMPLATE" "$ZELLIJ_CONFIG_FILE"

  log "Deploying zellij.zsh config..."
  mkdir -p "$ZSH_CONFIG_DIR"
  deploy_config "$SCRIPT_DIR/../config/zellij.zsh" "$ZSH_CONFIG_DIR/zellij.zsh"
}

clean() {
  brew uninstall zellij 2>/dev/null || true
  # Only remove the config glimt deployed (unless the user edited it), and
  # keep any layouts/themes the user added
  if [[ -f "$ZELLIJ_CONFIG_FILE" ]]; then
    if cmp -s "$ZELLIJ_CONFIG_FILE" "$KDL_TEMPLATE"; then
      rm -f "$ZELLIJ_CONFIG_FILE"
      log "Removed config: $ZELLIJ_CONFIG_FILE"
    else
      log "Kept edited config: $ZELLIJ_CONFIG_FILE"
    fi
  fi
  rmdir "$ZELLIJ_CONFIG_DIR" 2>/dev/null || true
  rm -f "$ZSH_CONFIG_DIR/zellij.zsh"
}

macos_guard

case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  *)
    echo "[$MODULE_NAME] unknown action: $ACTION" >&2
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
