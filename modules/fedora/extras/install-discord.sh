#!/bin/bash
set -e
trap 'echo "❌ Discord installation failed. Exiting." >&2' ERR

MODULE_NAME="discord"
ACTION="${1:-all}"

RPM_URL="https://discord.com/api/download?platform=linux&format=rpm"
TMP_RPM="/tmp/discord_latest.rpm"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || {
    echo "❌ This script supports Fedora/RHEL-based systems only."
    exit 1
  }
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# === Dependencies ===
DEPS=(curl libatomic libappindicator-gtk3 libcxx)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y "${DEPS[@]}" || true
}

install_discord() {
  echo "⬇️  Downloading Discord RPM..."
  curl -L "$RPM_URL" -o "$TMP_RPM"

  echo "📦 Installing Discord..."
  sudo dnf install -y "$TMP_RPM"

  echo "🧹 Cleaning up..."
  rm -f "$TMP_RPM"
  echo "✅ Discord installed."
}

config_discord() {
  echo "⚙️  Configuring Discord (no Fedora-specific tweaks yet)..."
}

clean_discord() {
  echo "🗑️  Removing Discord..."
  sudo dnf remove -y discord || true
}

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    install_discord
    ;;
  config)
    config_discord
    ;;
  clean)
    clean_discord
    ;;
  all)
    install_deps
    install_discord
    config_discord
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac


