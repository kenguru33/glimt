#!/bin/bash
set -e

MODULE_NAME="1password"
ACTION="${1:-all}"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Unable to detect OS."
  exit 1
fi

if [[ "$OS_ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
  echo "❌ This script supports Debian-based systems only."
  exit 1
fi

# === Constants ===
DEBIAN_KEYRING="/usr/share/keyrings/1password-archive-keyring.gpg"
DEBIAN_SOURCE="/etc/apt/sources.list.d/1password.list"
DEPS=(curl gnupg apt-transport-https)

# === Dependency Installer ===
install_deps() {
  echo "📦 Installing dependencies..."
  sudo apt update
  sudo apt install -y "${DEPS[@]}"
}

# === Install ===
install_1password() {
  echo "🔐 Installing 1Password for Debian..."

  echo "🔑 Importing GPG key..."
  sudo rm -f "$DEBIAN_KEYRING"
  curl -sS https://downloads.1password.com/linux/keys/1password.asc |
    sudo gpg --dearmor --output "$DEBIAN_KEYRING"

  echo "➕ Adding APT repo..."
  echo "deb [arch=amd64 signed-by=$DEBIAN_KEYRING] https://downloads.1password.com/linux/debian/amd64 stable main" |
    sudo tee "$DEBIAN_SOURCE" >/dev/null

  echo "📦 Installing 1Password..."
  sudo apt update
  sudo apt install -y 1password

  echo "✅ 1Password installed."
}

# === Clean ===
clean_1password() {
  echo "🧹 Removing 1Password..."

  sudo apt purge -y 1password || true
  sudo rm -f "$DEBIAN_SOURCE" "$DEBIAN_KEYRING"
  sudo apt update

  echo "✅ Clean complete."
}

# === Main Dispatcher ===
case "$ACTION" in
deps) install_deps ;;
install) install_1password ;;
clean) clean_1password ;;
all)
  install_deps
  install_1password
  ;;
*)
  echo "Usage: $0 [deps|install|clean|all]"
  exit 1
  ;;
esac
