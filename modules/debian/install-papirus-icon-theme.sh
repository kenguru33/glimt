#!/bin/bash
set -e

MODULE_NAME="papirus-icon-theme"
ACTION="${1:-all}"

# === Define dependencies ===
DEPS_DEBIAN=("papirus-icon-theme")

install_papirus() {
  echo "📦 Installing Papirus icon theme..."

  if command -v apt &>/dev/null; then
    sudo apt update
    sudo apt install -y "${DEPS_DEBIAN[@]}"
  else
    echo "❌ Unsupported distribution. Only Debian-based systems are supported."
    exit 1
  fi

  echo "✅ Papirus icon theme installed."
}

config_papirus() {
  echo "⚙️  Setting Papirus icon theme as default..."
  gsettings set org.gnome.desktop.interface icon-theme "Papirus"
  echo "✅ Papirus is now the default icon theme."
}

clean_papirus() {
  echo "🧹 Removing Papirus icon theme..."

  if command -v apt &>/dev/null; then
    sudo apt remove --purge -y "${DEPS_DEBIAN[@]}"
  else
    echo "❌ Unsupported distribution. Only Debian-based systems are supported."
    exit 1
  fi

  echo "✅ Papirus icon theme removed."
}

# === Entry point ===
case "$ACTION" in
install)
  install_papirus
  ;;
config)
  config_papirus
  ;;
clean)
  clean_papirus
  ;;
all)
  install_papirus
  config_papirus
  ;;
*)
  echo "Usage: $0 {install|config|clean|all}"
  exit 1
  ;;
esac
