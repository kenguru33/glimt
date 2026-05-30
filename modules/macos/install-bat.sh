#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="bat"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

BAT_THEME_NAME="Catppuccin Mocha"
THEME_VARIANTS=(Latte Frappe Macchiato Mocha)
THEME_REPO_BASE="https://github.com/catppuccin/bat/raw/main/themes"

deps() { log "No additional dependencies."; }

install() {
  log "Installing bat via Homebrew..."
  brew install bat
  verify_binary bat --version
}

config() {
  log "Installing Catppuccin themes for bat..."

  local bat_config_dir
  bat_config_dir="$(bat --config-dir)"
  local bat_theme_dir="$bat_config_dir/themes"
  local bat_config_file="$bat_config_dir/config"

  mkdir -p "$bat_theme_dir"

  for variant in "${THEME_VARIANTS[@]}"; do
    local theme_file="$bat_theme_dir/Catppuccin ${variant}.tmTheme"
    local theme_url="$THEME_REPO_BASE/Catppuccin%20${variant}.tmTheme"
    curl -fsSL -o "$theme_file" "$theme_url" || {
      warn "Failed to download Catppuccin ${variant} theme"
      continue
    }
  done

  bat cache --build || warn "Failed to rebuild bat theme cache"

  echo "--theme=\"$BAT_THEME_NAME\"" > "$bat_config_file"
  log "✅ Catppuccin themes installed, default set to $BAT_THEME_NAME"
}

clean() {
  local bat_config_dir
  bat_config_dir="$(bat --config-dir 2>/dev/null || echo "$HOME_DIR/.config/bat")"
  rm -rf "$bat_config_dir/themes" "$bat_config_dir/config" "$HOME_DIR/.cache/bat"
  brew uninstall bat 2>/dev/null || true
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
