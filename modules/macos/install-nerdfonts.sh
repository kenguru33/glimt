#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="nerdfonts"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

FONT_CASKS=(
  font-hack-nerd-font
  font-fira-code-nerd-font
  font-jetbrains-mono-nerd-font
  font-monaco-nerd-font
)

deps() { log "No additional dependencies."; }

install() {
  log "Installing Nerd Fonts via Homebrew..."
  for cask in "${FONT_CASKS[@]}"; do
    if brew list --cask "$cask" &>/dev/null; then
      log "$cask already installed."
    else
      brew install --cask "$cask" \
        || warn "$cask install failed — font files may already exist outside Homebrew, skipping"
      log "✅ $cask done"
    fi
  done
}

config() {
  log "No configuration needed. Fonts are available system-wide."
}

clean() {
  log "Removing Nerd Fonts..."
  for cask in "${FONT_CASKS[@]}"; do
    brew uninstall --cask "$cask" 2>/dev/null || true
  done
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
