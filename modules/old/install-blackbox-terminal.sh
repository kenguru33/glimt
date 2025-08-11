#!/bin/bash
set -e
trap 'echo "❌ An error occurred. Exiting." >&2' ERR

MODULE_NAME="blackbox-terminal"
SCHEME_DIR="$HOME/.local/share/blackbox/schemes"
PALETTE_NAME="Catppuccin Mocha"
PALETTE_FILE="catppuccin-mocha"
ACTION="${1:-all}"

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Could not detect operating system."
  exit 1
fi

# === Dependencies ===
DEPS_DEBIAN=(blackbox-terminal git gnome-settings-daemon gsettings-desktop-schemas)
DEPS_FEDORA=(blackbox-terminal git gsettings-desktop-schemas)

install_deps() {
  echo "📦 Installing dependencies for $OS_ID..."
  case "$OS_ID" in
    debian|ubuntu)
      sudo apt update
      sudo apt install -y "${DEPS_DEBIAN[@]}"
      ;;
    fedora)
      sudo dnf install -y "${DEPS_FEDORA[@]}"
      ;;
    *)
      echo "❌ Unsupported OS: $OS_ID"
      exit 1
      ;;
  esac
}

install_blackbox() {
  echo "🐧 Installing BlackBox Terminal..."

  if ! command -v blackbox &>/dev/null; then
    echo "⚠️ BlackBox binary not found after dependency install."
    echo "   It may not be available on this OS or version."
    return
  fi

  echo "✅ BlackBox is available: $(command -v blackbox)"
}

install_catppuccin_theme() {
  echo "🎨 Installing Catppuccin Mocha theme..."
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
    gsettings set $SCHEMA_ID font 'Hack Nerd Font Mono 11'
    gsettings set $SCHEMA_ID terminal-padding "(uint32 12, uint32 12, uint32 12, uint32 12)"
    gsettings set $SCHEMA_ID theme-dark "$PALETTE_NAME"
    gsettings set $SCHEMA_ID style-preference 2  # Force dark mode
    echo "✅ Configuration applied via GSettings."
  else
    echo "⚠️ GSettings schema '$SCHEMA_ID' not found. Skipping configuration."
    echo "ℹ️ Launch BlackBox once or reboot to register the schema."
  fi
}

clean_blackbox() {
  echo "🗑️ Cleaning up BlackBox terminal and theme files..."

  case "$OS_ID" in
    debian|ubuntu)
      sudo apt purge -y blackbox-terminal || true
      sudo apt autoremove -y
      ;;
    fedora)
      sudo dnf remove -y blackbox-terminal || true
      ;;
  esac

  rm -f "$SCHEME_DIR/$PALETTE_FILE.json"
  echo "✅ Cleanup done."
}

# === Entry Point ===
case "$ACTION" in
  deps) install_deps ;;
  install)
    install_blackbox
    install_catppuccin_theme
    ;;
  config) config_blackbox ;;
  clean) clean_blackbox ;;
  all)
    install_deps
    install_blackbox
    install_catppuccin_theme
    config_blackbox
    ;;
  *)
    echo "Usage: $0 [deps|install|config|clean|all]"
    exit 1
    ;;
esac
