#!/bin/bash
set -e
trap 'echo "❌ 1Password installation failed. Exiting." >&2' ERR

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

if [[ "$OS_ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$OS_ID" != "rhel" ]]; then
  echo "❌ This script supports Fedora/RHEL-based systems only."
  exit 1
fi

# === Constants ===
FEDORA_REPO="/etc/yum.repos.d/1password.repo"
FEDORA_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-1Password"
DEPS=(curl gnupg2)


# === Dependency Installer ===
install_deps() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y "${DEPS[@]}"
}

# === Install ===
install_1password() {
  echo "🔐 Installing 1Password for Fedora..."

  echo "🔑 Importing GPG key..."
  sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc

  echo "📁 Adding DNF repo..."
  sudo tee "$FEDORA_REPO" > /dev/null <<EOF
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

  echo "📦 Installing 1Password..."
  sudo dnf makecache -y
  sudo dnf install -y 1password

  echo "✅ 1Password installed."
}

# === Config ===
config_1password() {
  echo "⚙️  Configuring 1Password (no Fedora-specific tweaks yet)..."
}

# === Clean ===
clean_1password() {
  echo "🧹 Removing 1Password..."

  sudo dnf remove -y 1password || true
  sudo rm -f "$FEDORA_REPO"
  sudo rpm --erase gpg-pubkey-* 2>/dev/null || true

  echo "✅ Clean complete."
}

# === Main Dispatcher ===
case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    install_1password
    ;;
  config)
    config_1password
    ;;
  clean)
    clean_1password
    ;;
  all)
    install_deps
    install_1password
    config_1password
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

