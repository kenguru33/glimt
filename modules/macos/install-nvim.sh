#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="nvim"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

deps() { log "No additional dependencies."; }

install() {
  log "Installing Neovim, ripgrep, and fd via Homebrew..."
  brew install neovim ripgrep fd
  verify_binary nvim --version
}

config() {
  log "Deploying nvim.zsh config..."
  mkdir -p "$CONFIG_DIR"
  deploy_config "$SCRIPT_DIR/config/nvim.zsh" "$CONFIG_DIR/nvim.zsh"
}

clean() {
  brew uninstall neovim ripgrep fd 2>/dev/null || true
  rm -f "$CONFIG_DIR/nvim.zsh"
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
