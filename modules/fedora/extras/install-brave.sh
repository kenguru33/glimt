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

RPM_URL="https://brave-browser-apt-release.s3.brave.com/brave-browser.rpm"
TMP_RPM="/tmp/brave-browser-latest.rpm"

deps() {
  echo "🔧 [$MODULE_NAME] Installing dependencies…"
  sudo dnf makecache -y
  sudo dnf install -y curl
}

install_pkg() {
  echo "📦 [$MODULE_NAME] Installing Brave browser via RPM…"
  curl -L "$RPM_URL" -o "$TMP_RPM"
  sudo dnf install -y "$TMP_RPM"
}

config() {
  echo "⚙️  [$MODULE_NAME] No special Brave config for Fedora yet."
}

clean() {
  echo "🧹 [$MODULE_NAME] Removing Brave…"
  sudo dnf remove -y brave-browser || true
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


