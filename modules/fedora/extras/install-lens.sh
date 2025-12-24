#!/bin/bash
set -e
trap 'echo "❌ Lens installation failed. Exiting." >&2' ERR

MODULE_NAME="lens"
ACTION="${1:-all}"

# === Detect OS ===
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

# Determine architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    RPM_URL="https://downloads.k8slens.dev/releases/Lens-latest.x86_64.rpm"
    TMP_RPM="/tmp/Lens-latest.x86_64.rpm"
    ;;
  aarch64)
    RPM_URL="https://downloads.k8slens.dev/releases/Lens-latest.aarch64.rpm"
    TMP_RPM="/tmp/Lens-latest.aarch64.rpm"
    ;;
  *)
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

install_deps() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y curl
}

install_lens() {
  echo "📦 Installing Lens Desktop (RPM)..."

  if command -v lens-desktop &>/dev/null || command -v lens &>/dev/null; then
    echo "✅ Lens is already installed."
    return
  fi

  echo "⬇️ Downloading Lens RPM..."
  curl -L "$RPM_URL" -o "$TMP_RPM"

  echo "📦 Installing RPM..."
  sudo dnf install -y "$TMP_RPM"

  echo "🧹 Cleaning up..."
  rm -f "$TMP_RPM"
  echo "✅ Lens Desktop installed."
}

config_lens() {
  echo "⚙️  Configuring Lens (no Fedora-specific tweaks yet)..."
}

clean_lens() {
  echo "🧹 Removing Lens Desktop..."
  sudo dnf remove -y lens-desktop lens || true
  echo "✅ Lens Desktop removed."
}

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    install_lens
    ;;
  config)
    config_lens
    ;;
  clean)
    clean_lens
    ;;
  all)
    install_deps
    install_lens
    config_lens
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac


