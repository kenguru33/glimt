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

# Lens repository configuration
LENS_REPO="/etc/yum.repos.d/lens.repo"
LENS_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-lens"

install_deps() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y curl gnupg2
}

install_lens() {
  echo "📦 Installing Lens Desktop..."

  if command -v lens-desktop &>/dev/null || command -v lens &>/dev/null; then
    echo "✅ Lens is already installed."
    return
  fi

  echo "🔑 Importing GPG key..."
  curl -fsSL https://downloads.k8slens.dev/keys/gpg | sudo gpg --dearmor -o "$LENS_KEY" 2>/dev/null || \
    curl -fsSL https://downloads.k8slens.dev/keys/gpg | sudo rpm --import - 2>/dev/null || true

  echo "📁 Adding DNF repository..."
  sudo tee "$LENS_REPO" > /dev/null <<EOF
[lens]
name=Lens Desktop
baseurl=https://downloads.k8slens.dev/rpm/stable/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.k8slens.dev/keys/gpg
EOF

  echo "🔄 Updating package lists..."
  sudo dnf makecache -y

  echo "⬇️ Installing Lens..."
  sudo dnf install -y lens

  echo "✅ Lens Desktop installed."
}

config_lens() {
  echo "⚙️  Configuring Lens (no Fedora-specific tweaks yet)..."
}

clean_lens() {
  echo "🧹 Removing Lens Desktop..."
  sudo dnf remove -y lens-desktop lens || true
  sudo rm -f "$LENS_REPO" "$LENS_KEY"
  sudo dnf makecache -y
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


