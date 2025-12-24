#!/bin/bash
set -e
trap 'echo "❌ 1Password CLI installation failed. Exiting." >&2' ERR

MODULE_NAME="1password-cli"
ACTION="${1:-all}"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Unable to detect OS."
  exit 1
fi

if [[ "$OS_ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$OS_ID" != "rhel" ]]; then
  echo "❌ This script supports Fedora/RHEL-based systems only."
  exit 1
fi

# === Constants ===
FEDORA_REPO="/etc/yum.repos.d/1password-cli.repo"
DEPS=(curl gnupg2)


# === Dependencies ===
install_deps() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y "${DEPS[@]}"
}

# === Install ===
install_cli() {
  echo "🔐 Installing 1Password CLI..."

  echo "🔑 Importing GPG key..."
  sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc

  echo "📁 Adding DNF repo..."
  sudo tee "$FEDORA_REPO" > /dev/null <<EOF
[1password-cli]
name=1Password CLI Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

  echo "📦 Installing 1Password CLI..."
  sudo dnf makecache -y
  sudo dnf install -y 1password-cli

  echo "✅ 1Password CLI installed."
  echo "💡 Run 'op signin' to get started."
}

# === Config ===
config_cli() {
  echo "⚙️  Configuring 1Password CLI..."
  if command -v op &>/dev/null; then
    echo "✅ 1Password CLI is installed and ready to use."
    echo "💡 Run 'op signin' to authenticate."
  else
    echo "❌ 1Password CLI not found. Please install it first."
    exit 1
  fi
}

# === Clean ===
clean_cli() {
  echo "🧹 Removing 1Password CLI..."

  sudo dnf remove -y 1password-cli || true
  sudo rm -f "$FEDORA_REPO"
  sudo rpm --erase gpg-pubkey-* 2>/dev/null || true

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
  config)
    config_cli
    ;;
  clean)
    clean_cli
    ;;
  all)
    install_deps
    install_cli
    config_cli
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

