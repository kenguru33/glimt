#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

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
  local latest current=""
  latest="$(curl -fsSL https://api.github.com/repos/volta-cli/volta/releases/latest 2>/dev/null |
    sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1)" || latest=""
  if [[ -x "$VOLTA_HOME/bin/volta" ]]; then
    current="$("$VOLTA_HOME/bin/volta" --version 2>/dev/null || true)"
    if [[ -z "$latest" || "$current" == "$latest" ]]; then
      log "Volta ${current:-} is up to date."
      return 0
    fi
    log "Updating Volta $current → $latest..."
  else
    log "Installing Volta..."
  fi
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
    echo "[$MODULE_NAME] unknown action: $ACTION" >&2
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
