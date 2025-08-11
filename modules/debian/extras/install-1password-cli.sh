#!/bin/bash
set -e

MODULE_NAME="1password-cli"
ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
KEYRING="/usr/share/keyrings/1password-archive-keyring.gpg"
REPO_LIST="/etc/apt/sources.list.d/1password.list"
POLICY_DIR="/etc/debsig/policies/AC2D62742012EA22"
POLICY_FILE="$POLICY_DIR/1password.pol"
KEYRING_DIR="/usr/share/debsig/keyrings/AC2D62742012EA22"
DEBSIG_KEY="$KEYRING_DIR/debsig.gpg"
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

# === Dependencies ===
DEPS=(curl gnupg apt-transport-https debsig-verify)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo apt update
  sudo apt install -y "${DEPS[@]}"
}

install_cli() {
  echo "🔐 Installing 1Password CLI..."

  echo "🔑 Importing GPG key and setting up APT repo..."
  sudo mkdir -p "$(dirname "$KEYRING")"
  curl -sS https://downloads.1password.com/linux/keys/1password.asc |
    gpg --dearmor | sudo tee "$KEYRING" >/dev/null

  echo "📁 Adding APT repo..."
  echo "deb [arch=$ARCH signed-by=$KEYRING] https://downloads.1password.com/linux/debian/$ARCH stable main" |
    sudo tee "$REPO_LIST" >/dev/null

  echo "📜 Adding debsig policy..."
  sudo mkdir -p "$POLICY_DIR"
  curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol |
    sudo tee "$POLICY_FILE" >/dev/null

  echo "🔑 Adding debsig GPG key..."
  sudo mkdir -p "$KEYRING_DIR"
  curl -sS https://downloads.1password.com/linux/keys/1password.asc |
    gpg --dearmor | sudo tee "$DEBSIG_KEY" >/dev/null

  echo "📦 Installing via APT..."
  sudo apt update
  sudo apt install -y 1password-cli

  echo "✅ 1Password CLI installed."
}

clean_cli() {
  echo "🧹 Removing 1Password CLI..."

  sudo apt remove -y 1password-cli
  sudo rm -f "$REPO_LIST" "$KEYRING"
  sudo rm -f "$POLICY_FILE" "$DEBSIG_KEY"
  sudo rm -rf "$POLICY_DIR" "$KEYRING_DIR"
  sudo apt update

  echo "✅ 1Password CLI removed."
}

# === Dispatcher ===
case "$ACTION" in
deps)
  install_deps
  ;;
install)
  install_deps
  install_cli
  ;;
clean)
  clean_cli
  ;;
all)
  install_deps
  install_cli
  ;;
*)
  echo "Usage: $0 [deps|install|clean|all]"
  exit 1
  ;;
esac
