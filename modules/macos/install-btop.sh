#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="btop"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

BTOP_CONFIG_DIR="$HOME_DIR/.config/btop"
BTOP_THEME_DIR="$BTOP_CONFIG_DIR/themes"
BTOP_CONFIG_FILE="$BTOP_CONFIG_DIR/btop.conf"

deps() { log "No additional dependencies."; }

install() {
  log "Installing btop via Homebrew..."
  brew install btop
  verify_binary btop --version
}

config() {
  mkdir -p "$BTOP_THEME_DIR"

  log "Downloading Catppuccin Mocha theme..."
  curl -fsSL https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_mocha.theme \
    -o "$BTOP_THEME_DIR/catppuccin_mocha.theme"

  if [[ ! -f "$BTOP_CONFIG_FILE" ]]; then
    btop --write-config </dev/null >/dev/null 2>&1 || \
      printf 'color_theme = "catppuccin_mocha"\n' > "$BTOP_CONFIG_FILE"
  fi

  if grep -q '^color_theme' "$BTOP_CONFIG_FILE" 2>/dev/null; then
    sed -i '' 's/^color_theme.*/color_theme = "catppuccin_mocha"/' "$BTOP_CONFIG_FILE"
  else
    printf 'color_theme = "catppuccin_mocha"\n' >> "$BTOP_CONFIG_FILE"
  fi

  log "Theme set to catppuccin_mocha."
}

clean() {
  brew uninstall btop 2>/dev/null || true
  rm -f "$BTOP_THEME_DIR/catppuccin_mocha.theme"
  rm -f "$BTOP_CONFIG_FILE"
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
