#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="fzf"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

CONFIG_DIR="$HOME_DIR/.zsh/config"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

deps() { log "No additional dependencies."; }

install() {
  log "Installing fzf and fd via Homebrew..."
  brew install fzf fd
  verify_binary fzf --version

  log "Installing fzf-tab plugin..."
  local fzf_tab_dir="$PLUGIN_DIR/fzf-tab"
  if [[ -d "$fzf_tab_dir/.git" ]]; then
    log "Updating fzf-tab..."
    git -C "$fzf_tab_dir" pull --quiet --rebase
  else
    rm -rf "$fzf_tab_dir"
    git clone --depth=1 https://github.com/Aloxaf/fzf-tab "$fzf_tab_dir"
  fi
}

config() {
  log "Deploying fzf.zsh config..."
  mkdir -p "$CONFIG_DIR"
  deploy_config "$SCRIPT_DIR/config/fzf.zsh" "$CONFIG_DIR/fzf.zsh"
}

clean() {
  brew uninstall fzf fd 2>/dev/null || true
  rm -rf "$PLUGIN_DIR/fzf-tab" "$CONFIG_DIR/fzf.zsh"
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
