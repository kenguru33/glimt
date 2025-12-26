#!/bin/bash
set -e
trap 'echo "❌ TablePlus installation failed. Exiting." >&2' ERR

MODULE_NAME="tableplus"
ACTION="${1:-all}"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Could not detect operating system."
  exit 1
fi

if [[ "$OS_ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$OS_ID" != "rhel" ]]; then
  echo "❌ This script supports Fedora/RHEL-based systems only."
  exit 1
fi

TABLEPLUS_REPO="/etc/yum.repos.d/tableplus.repo"
TABLEPLUS_GPG_KEY_URL="https://yum.tableplus.com/apt.tableplus.com.gpg.key"
TABLEPLUS_REPOFILE_URL="https://yum.tableplus.com/rpm/x86_64/tableplus.repo"

install_deps() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y dnf-plugins-core
}

install_tableplus() {
  echo "🧰 Installing TablePlus..."

  if command -v tableplus &>/dev/null || rpm -q tableplus &>/dev/null; then
    echo "✅ TablePlus is already installed."
    return
  fi

  echo "🔑 Importing GPG key..."
  sudo rpm -v --import "$TABLEPLUS_GPG_KEY_URL"

  echo "📁 Adding TablePlus repository..."
  if [[ -f "$TABLEPLUS_REPO" ]]; then
    echo "ℹ️  TablePlus repo already exists, removing old one..."
    sudo rm -f "$TABLEPLUS_REPO"
  fi

  # Using the same pattern as other Fedora extras (dnf config-manager addrepo --from-repofile=...)
  sudo dnf config-manager addrepo --from-repofile="$TABLEPLUS_REPOFILE_URL"

  echo "🔄 Updating package lists..."
  sudo dnf makecache -y

  echo "⬇️  Installing TablePlus..."
  sudo dnf install -y tableplus

  echo "✅ TablePlus installed."
}

config_tableplus() {
  echo "⚙️  Configuring TablePlus (no Fedora-specific tweaks yet)..."
}

clean_tableplus() {
  echo "🧹 Removing TablePlus..."
  sudo dnf remove -y tableplus || true
  if [[ -f "$TABLEPLUS_REPO" ]]; then
    sudo rm -f "$TABLEPLUS_REPO"
    sudo dnf makecache -y || true
  fi
  echo "✅ TablePlus removed."
}

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    install_tableplus
    ;;
  config)
    config_tableplus
    ;;
  clean)
    clean_tableplus
    ;;
  all)
    install_deps
    install_tableplus
    config_tableplus
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac


