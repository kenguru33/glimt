#!/bin/bash
set -e

MODULE_NAME="lens"
ACTION="${1:-all}"

APT_SOURCE="/etc/apt/sources.list.d/lens.list"
KEYRING="/usr/share/keyrings/lens-archive-keyring.gpg"

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Could not detect operating system."
  exit 1
fi

if [[ "$OS_ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
  echo "❌ This script supports Debian-based systems only."
  exit 1
fi

# === Dependencies ===
DEPS=(curl gnupg apt-transport-https)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo apt update
  sudo apt install -y "${DEPS[@]}"
}

install_lens() {
  echo "📦 Installing Lens Desktop..."

  if command -v lens &>/dev/null; then
    echo "✅ Lens is already installed."
    return
  fi

  echo "🔑 Adding GPG key..."
  curl -fsSL https://downloads.k8slens.dev/keys/gpg | gpg --dearmor | sudo tee "$KEYRING" >/dev/null

  echo "📁 Adding APT source..."
  echo "deb [arch=amd64 signed-by=$KEYRING] https://downloads.k8slens.dev/apt/debian stable main" |
    sudo tee "$APT_SOURCE" >/dev/null

  echo "🔄 Updating package lists..."
  sudo apt update

  echo "⬇️ Installing Lens..."
  sudo apt install -y lens

  echo "✅ Lens Desktop installed."
}

clean_lens() {
  echo "🧹 Removing Lens Desktop..."

  sudo apt remove -y lens || true
  sudo rm -f "$APT_SOURCE" "$KEYRING"
  sudo apt update

  echo "✅ Lens Desktop removed."
}

# === Entry point ===
case "$ACTION" in
deps)
  install_deps
  ;;
install)
  install_lens
  ;;
clean)
  clean_lens
  ;;
all)
  install_deps
  install_lens
  ;;
*)
  echo "Usage: $0 [deps|install|clean|all]"
  exit 1
  ;;
esac
