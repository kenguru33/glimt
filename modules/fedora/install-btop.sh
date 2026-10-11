#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="btop"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

BTOP_CONFIG_DIR="$HOME_DIR/.config/btop"
BTOP_THEME_DIR="$BTOP_CONFIG_DIR/themes"
BTOP_CONFIG_FILE="$BTOP_CONFIG_DIR/btop.conf"

deps() {
  log "Installing btop..."
  sudo dnf install -y btop
}

install() {
  verify_binary btop --version
}

config() {
  run_as_user mkdir -p "$BTOP_THEME_DIR"

  log "Downloading Catppuccin Mocha theme..."
  run_as_user curl -fsSL https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_mocha.theme \
    -o "$BTOP_THEME_DIR/catppuccin_mocha.theme"

  if [[ ! -f "$BTOP_CONFIG_FILE" ]]; then
    run_as_user bash -c "env TERM=xterm-256color btop --write-config </dev/null >/dev/null 2>&1" || \
      run_as_user bash -c "printf 'color_theme = \"catppuccin_mocha\"\n' > \"$BTOP_CONFIG_FILE\""
  fi

  if run_as_user grep -q '^color_theme' "$BTOP_CONFIG_FILE" 2>/dev/null; then
    run_as_user sed -i 's/^color_theme.*/color_theme = "catppuccin_mocha"/' "$BTOP_CONFIG_FILE"
  else
    run_as_user bash -c "printf 'color_theme = \"catppuccin_mocha\"\n' >> \"$BTOP_CONFIG_FILE\""
  fi

  log "Theme set to catppuccin_mocha."
}

clean() {
  run_as_user rm -f "$BTOP_THEME_DIR/catppuccin_mocha.theme"
  run_as_user rm -f "$BTOP_CONFIG_FILE"
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
