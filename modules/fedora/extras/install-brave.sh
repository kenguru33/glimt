#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="brave"
ACTION="${1:-all}"

fedora_guard() {
  [[ -r /etc/os-release ]] || {
    echo "❌ /etc/os-release missing"
    exit 1
  }
  . /etc/os-release
  [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || {
    echo "❌ Fedora/RHEL-based systems only."
    exit 1
  }
}

BRAVE_REPO="/etc/yum.repos.d/brave-browser.repo"

deps() {
  echo "🔧 [$MODULE_NAME] Installing dependencies…"
  sudo dnf makecache -y
  sudo dnf install -y dnf-plugins-core curl
}

install_pkg() {
  echo "📦 [$MODULE_NAME] Installing Brave browser via repository…"
  
  if command -v brave-browser &>/dev/null; then
    echo "✅ Brave browser is already installed."
    return
  fi
  
  echo "🔑 Importing GPG key..."
  sudo rpm --import https://brave-browser-apt-release.s3.brave.com/brave-core.asc
  
  echo "📁 Adding Brave repository..."
  if [[ -f "$BRAVE_REPO" ]]; then
    echo "ℹ️  Brave repository already exists, removing old one..."
    sudo rm -f "$BRAVE_REPO"
  fi
  
  sudo tee "$BRAVE_REPO" > /dev/null <<EOF
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-apt-release.s3.brave.com/rpm/
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-apt-release.s3.brave.com/brave-core.asc
EOF

  echo "🔄 Updating package lists..."
  sudo dnf makecache -y

  echo "⬇️ Installing Brave browser..."
  sudo dnf install -y brave-browser

  echo "✅ Brave browser installed."
}

config() {
  echo "⚙️  [$MODULE_NAME] No special Brave config for Fedora yet."
}

clean() {
  echo "🧹 [$MODULE_NAME] Removing Brave…"
  sudo dnf remove -y brave-browser || true
  if [[ -f "$BRAVE_REPO" ]]; then
    sudo rm -f "$BRAVE_REPO"
    sudo dnf makecache -y
  fi
  echo "✅ Brave browser removed."
}

all() {
  deps
  install_pkg
  config
  echo "✅ [$MODULE_NAME] Done."
}

fedora_guard

case "$ACTION" in
  deps) deps ;;
  install) install_pkg ;;
  config) config ;;
  clean) clean ;;
  all) all ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 2
    ;;
esac


