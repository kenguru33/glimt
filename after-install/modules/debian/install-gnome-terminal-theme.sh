#!/bin/bash
set -e
trap 'echo "❌ ${MODULE_NAME} failed at $BASH_COMMAND" >&2' ERR

MODULE_NAME="gnome-terminal-catppuccin"
ACTION="${1:-all}"

# === Paths ===
FONT_NAME="Hack Nerd Font Mono"
FONT_SIZE=12
PALETTE_NAME="Catppuccin Mocha"

# === Dependencies ===
DEPS=(gnome-terminal dconf-cli)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo apt update -y
  sudo apt install -y "${DEPS[@]}"
}

install() {
  echo "📥 No separate install step for ${MODULE_NAME}."
}

config() {
  echo "🎨 Applying ${PALETTE_NAME} + ${FONT_NAME} to GNOME Terminal..."

  if ! command -v gnome-terminal &>/dev/null; then
    echo "❌ GNOME Terminal not found. Skipping."
    return
  fi

  # Get default GNOME Terminal profile UUID
  local uuid
  uuid=$(gsettings get org.gnome.Terminal.ProfilesList default)
  uuid=${uuid:1:-1}

  # Disable theme colors
  dconf write "/org/gnome/terminal/legacy/profiles:/:${uuid}/use-theme-colors" false

  # Set Catppuccin Mocha palette
  dconf write "/org/gnome/terminal/legacy/profiles:/:${uuid}/foreground-color" "'#CDD6F4'"
  dconf write "/org/gnome/terminal/legacy/profiles:/:${uuid}/background-color" "'#1E1E2E'"
  dconf write "/org/gnome/terminal/legacy/profiles:/:${uuid}/palette" "[
      '#1E1E2E', '#F38BA8', '#A6E3A1', '#F9E2AF',
      '#89B4FA', '#F5C2E7', '#94E2D5', '#BAC2DE',
      '#585B70', '#F38BA8', '#A6E3A1', '#F9E2AF',
      '#89B4FA', '#F5C2E7', '#94E2D5', '#A6ADC8'
    ]"

  # Optional: bold and cursor colors
  dconf write "/org/gnome/terminal/legacy/profiles:/:${uuid}/bold-color" "'#F5E0DC'"
  dconf write "/org/gnome/terminal/legacy/profiles:/:${uuid}/cursor-background-color" "'#F5E0DC'"
  dconf write "/org/gnome/terminal/legacy/profiles:/:${uuid}/cursor-foreground-color" "'#1E1E2E'"

  # Set font
  #dconf write "/org/gnome/terminal/legacy/profiles:/:${uuid}/use-system-font" false
  #dconf write "/org/gnome/terminal/legacy/profiles:/:${uuid}/font" "'${FONT_NAME} ${FONT_SIZE}'"

  echo "✅ ${PALETTE_NAME} colors + ${FONT_NAME} applied."
}

clean() {
  echo "🗑 No clean step for ${MODULE_NAME}."
}

# === Action Selector ===
case "$ACTION" in
all)
  install_deps
  install
  config
  ;;
deps) install_deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
