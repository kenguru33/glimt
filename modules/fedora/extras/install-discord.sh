#!/bin/bash
set -e
trap 'echo "❌ Discord installation failed. Exiting." >&2' ERR

MODULE_NAME="discord"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

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
DEPS=(libatomic libappindicator-gtk3 libcxx)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  
  # Check if RPM Fusion is enabled
  if ! rpm -q rpmfusion-free-release &>/dev/null && ! rpm -q rpmfusion-nonfree-release &>/dev/null; then
    echo "📁 Adding RPM Fusion repository..."
    FEDORA_VERSION=$(rpm -E %fedora 2>/dev/null || echo "")
    if [[ -n "$FEDORA_VERSION" ]]; then
      sudo dnf install -y "https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm" || true
    else
      echo "⚠️  Could not determine Fedora version, trying generic RPM Fusion setup..."
      sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm || true
    fi
  fi
  
  sudo dnf install -y "${DEPS[@]}" || true
}

install_discord() {
  echo "📦 Installing Discord from RPM Fusion..."
  
  if command -v discord &>/dev/null; then
    echo "✅ Discord is already installed."
    return
  fi
  
  # Ensure RPM Fusion is available
  if ! dnf list --available discord &>/dev/null; then
    echo "⚠️  Discord not found in repositories. Adding RPM Fusion..."
    install_deps
  fi
  
  echo "⬇️  Installing Discord..."
  sudo dnf install -y discord
  
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


