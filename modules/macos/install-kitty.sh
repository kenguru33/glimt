#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="kitty"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KITTY_CONFIG_DIR="$HOME_DIR/.config/kitty"

deps() { log "No additional dependencies."; }

install() {
  if brew list --cask kitty &>/dev/null; then
    log "Kitty already installed."
  else
    brew install --cask kitty
  fi
  verify_binary kitty --version
}

config() {
  mkdir -p "$KITTY_CONFIG_DIR"
  deploy_config "$SCRIPT_DIR/config/kitty.conf" "$KITTY_CONFIG_DIR/kitty.conf"

  local app="/Applications/kitty.app"
  if [[ ! -d "$app" ]]; then
    warn "kitty.app not found in /Applications — skipping icon."
    return 0
  fi

  log "Applying DinkDonk kitty-dark icon..."
  # Set a *custom* icon via fileicon (NSWorkspace) instead of replacing the
  # bundle's .icns: it overrides the app icon, refreshes immediately, and does
  # not break the app's code signature or fight the macOS icon cache. Cosmetic,
  # so any failure here warns instead of aborting. Needs App Management
  # permission for the terminal (see the notice shown by setup-macos.sh).
  if ! command -v fileicon &>/dev/null; then
    brew install fileicon >/dev/null 2>&1 || true
  fi

  local tmp_icon
  tmp_icon="$(mktemp)"
  if command -v fileicon &>/dev/null \
     && curl -fsSL https://raw.githubusercontent.com/DinkDonk/kitty-icon/main/kitty-dark.icns -o "$tmp_icon" \
     && fileicon set "$app" "$tmp_icon" >/dev/null 2>&1; then
    killall Dock 2>/dev/null || true
    killall Finder 2>/dev/null || true
    log "Icon applied."
  else
    warn "Could not apply kitty icon (needs fileicon + App Management permission) — skipping."
  fi
  rm -f "$tmp_icon"
}

clean() {
  command -v fileicon &>/dev/null && fileicon rm /Applications/kitty.app 2>/dev/null || true
  brew uninstall --cask kitty 2>/dev/null || true
  rm -f "$KITTY_CONFIG_DIR/kitty.conf"
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
