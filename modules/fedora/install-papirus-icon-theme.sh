#!/bin/bash
set -e

MODULE_NAME="papirus-icon-theme"
ACTION="${1:-all}"

# === OS detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This script supports Fedora/RHEL-based systems only."
  exit 1
fi

install_papirus() {
  echo "📦 Installing Papirus icon theme (dnf)..."
  sudo dnf makecache -y
  sudo dnf install -y papirus-icon-theme
  echo "✅ Papirus icon theme installed."
}

config_papirus() {
  echo "⚙️  Setting Papirus icon theme as default..."
  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface icon-theme "Papirus"
    echo "✅ Papirus is now the default icon theme."
  else
    echo "⚠️ gsettings not available; cannot set theme automatically."
  fi
}

clean_papirus() {
  echo "🧹 Removing Papirus icon theme..."
  sudo dnf remove -y papirus-icon-theme || true
  echo "✅ Papirus icon theme removed."
}

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


