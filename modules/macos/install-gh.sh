#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="gh"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

CONFIG_DIR="$HOME_DIR/.zsh/config"
COMPLETION_DIR="$HOME_DIR/.zsh/plugins/gh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

deps() { log "No additional dependencies."; }

install() {
  log "Installing GitHub CLI via Homebrew..."
  brew install gh
  verify_binary gh --version
}

config() {
  log "Generating gh zsh completion..."
  mkdir -p "$COMPLETION_DIR"
  gh completion -s zsh > "$COMPLETION_DIR/_gh"

  log "Deploying gh.zsh config..."
  mkdir -p "$CONFIG_DIR"
  deploy_config "$SCRIPT_DIR/config/gh.zsh" "$CONFIG_DIR/gh.zsh"
}

clean() {
  brew uninstall gh 2>/dev/null || true
  rm -rf "$COMPLETION_DIR" "$CONFIG_DIR/gh.zsh"
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
