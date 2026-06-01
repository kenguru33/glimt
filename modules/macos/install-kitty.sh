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

# Replacing the .icns inside a bundle is not enough — macOS caches app icons.
# Re-register the app and flush the icon caches so the new icon shows.
refresh_icon_cache() {
  local app="$1"
  touch "$app" 2>/dev/null || sudo touch "$app" 2>/dev/null || true

  local lsreg="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
  [[ -x "$lsreg" ]] && "$lsreg" -f "$app" 2>/dev/null || true

  # System icon services cache (needs root) + per-user dock cache.
  sudo rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true
  local user_cache
  user_cache="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
  [[ -n "$user_cache" ]] && find "$user_cache" -name 'com.apple.dock.iconcache' -delete 2>/dev/null || true

  killall Dock 2>/dev/null || true
  killall Finder 2>/dev/null || true
}

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
  local icon_dest="$app/Contents/Resources/kitty.icns"
  if [[ -d "$app" ]]; then
    log "Applying DinkDonk kitty-dark icon..."
    # Download to a temp file first — curl can't write directly into the app
    # bundle (not user-writable, which caused "curl: (56) Failure writing
    # output to destination"). Then copy into place, falling back to sudo. The
    # icon is cosmetic, so any failure here warns instead of aborting setup.
    local tmp_icon
    tmp_icon="$(mktemp)"
    if curl -fsSL https://raw.githubusercontent.com/DinkDonk/kitty-icon/main/kitty-dark.icns -o "$tmp_icon" \
       && { cp -f "$tmp_icon" "$icon_dest" 2>/dev/null || sudo cp -f "$tmp_icon" "$icon_dest"; }; then
      refresh_icon_cache "$app"
      log "Icon applied — icon caches flushed (Dock/Finder restarted)."
    else
      warn "Could not apply kitty icon — skipping (non-fatal)."
    fi
    rm -f "$tmp_icon"
  else
    warn "kitty.app not found in /Applications — skipping icon."
  fi
}

clean() {
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
