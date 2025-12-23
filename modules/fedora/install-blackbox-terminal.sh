#!/bin/bash
set -e
trap 'echo "❌ An error occurred. Exiting." >&2' ERR

MODULE_NAME="blackbox-terminal"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCHEME_DIR="$HOME/.local/share/blackbox/schemes"
PALETTE_NAME="Catppuccin Mocha"
PALETTE_FILE="catppuccin-mocha"
FONT_NAME="Hack Nerd Font Mono"
NERDFONT_INSTALLER="$SCRIPT_DIR/install-nerdfonts.sh"
ACTION="${1:-all}"

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Could not detect operating system."
  exit 1
fi

# === Ensure Fedora/RHEL-like ===
if [[ "$OS_ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$OS_ID" != "rhel" ]]; then
  echo "⚠️ This module only supports Fedora/RHEL. Skipping."
  exit 0
fi

# === Dependencies ===
DEPS=(blackbox-terminal git gsettings-desktop-schemas)

install_deps() {
  echo "📦 Installing dependencies for Fedora..."
  sudo dnf makecache -y
  sudo dnf install -y "${DEPS[@]}"
}

install_blackbox() {
  echo "🐧 Ensuring BlackBox Terminal is installed..."

  if ! command -v blackbox-terminal &>/dev/null; then
    echo "⚠️ blackbox-terminal binary not found after dependency install."
    echo "   It may not be available on this OS or version."
    return
  fi

  echo "✅ BlackBox is available: $(command -v blackbox-terminal)"
}

check_font_installed() {
  echo "🔍 Checking for required font: $FONT_NAME..."
  if fc-list | grep -i -q "$FONT_NAME"; then
    echo "✅ Font '$FONT_NAME' is installed."
    return
  fi

  echo "❌ '$FONT_NAME' not found. Running Nerd Font installer..."
  if [[ -x "$NERDFONT_INSTALLER" ]]; then
    "$NERDFONT_INSTALLER" install
  else
    echo "❌ Missing or non-executable script: $NERDFONT_INSTALLER"
    exit 1
  fi

  # Re-check after install
  if fc-list | grep -i -q "$FONT_NAME"; then
    echo "✅ Font '$FONT_NAME' installed successfully."
  else
    echo "❌ Failed to detect '$FONT_NAME' after install."
    exit 1
  fi
}

install_catppuccin_theme() {
  echo "🎨 Installing Catppuccin Mocha theme for BlackBox..."
  mkdir -p "$SCHEME_DIR"

  if [[ ! -f "$SCHEME_DIR/$PALETTE_FILE.json" ]]; then
    TMP_DIR=$(mktemp -d)
    git clone --depth=1 https://github.com/catppuccin/tilix.git "$TMP_DIR"
    cp "$TMP_DIR/themes/$PALETTE_FILE.json" "$SCHEME_DIR/$PALETTE_FILE.json"
    rm -rf "$TMP_DIR"
    echo "✅ Theme installed to $SCHEME_DIR"
  else
    echo "ℹ️ Theme already installed."
  fi
}

config_blackbox() {
  echo "🎨 Configuring BlackBox with Catppuccin Mocha + Hack Nerd Font Mono..."
  SCHEMA_ID="com.raggesilver.BlackBox"

  if gsettings list-schemas | grep -q "$SCHEMA_ID"; then
    gsettings set "$SCHEMA_ID" font "$FONT_NAME 11"
    gsettings set "$SCHEMA_ID" terminal-padding "(uint32 12, uint32 12, uint32 12, uint32 12)"
    gsettings set "$SCHEMA_ID" theme-dark "$PALETTE_NAME"
    gsettings set "$SCHEMA_ID" style-preference 2     # Force dark mode
    gsettings set "$SCHEMA_ID" easy-copy-paste true
    echo "✅ Configuration applied via GSettings."
  else
    echo "⚠️ GSettings schema '$SCHEMA_ID' not found. Skipping configuration."
    echo "ℹ️ Launch BlackBox once or reboot to register the schema."
  fi

  # Make BlackBox the default terminal (where applicable)
  gsettings set org.gnome.desktop.default-applications.terminal exec 'blackbox-terminal' || true
  gsettings set org.gnome.desktop.default-applications.terminal exec-arg '' || true
}

clean_blackbox() {
  echo "🗑️ Cleaning up BlackBox terminal and theme files..."

  # Remove theme file
  rm -f "$SCHEME_DIR/$PALETTE_FILE.json"

  # Remove the package (best-effort)
  sudo dnf remove -y blackbox-terminal || true

  echo "✅ Cleanup done."
}

# === Entry Point ===
case "$ACTION" in
  deps) install_deps ;;
  install)
    install_deps
    install_blackbox
    check_font_installed
    install_catppuccin_theme
    ;;
  config)
    check_font_installed
    config_blackbox
    ;;
  clean) clean_blackbox ;;
  all)
    install_deps
    install_blackbox
    check_font_installed
    install_catppuccin_theme
    config_blackbox
    ;;
  *)
    echo "Usage: $0 [deps|install|config|clean|all]"
    exit 1
    ;;
esac


