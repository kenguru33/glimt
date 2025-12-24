#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="vscode"
ACTION="${1:-all}"

# Determine architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    RPM_URL="https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-x64"
    TMP_RPM="/tmp/vscode-latest.x86_64.rpm"
    ;;
  aarch64)
    RPM_URL="https://code.visualstudio.com/sha/download?build=stable&os=linux-rpm-arm64"
    TMP_RPM="/tmp/vscode-latest.aarch64.rpm"
    ;;
  *)
    echo "❌ Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

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

deps() {
  echo "🔧 [$MODULE_NAME] Installing dependencies…"
  sudo dnf makecache -y
  sudo dnf install -y curl
}

install_pkg() {
  echo "📦 [$MODULE_NAME] Installing VS Code via RPM…"
  curl -L "$RPM_URL" -o "$TMP_RPM"
  sudo dnf install -y "$TMP_RPM"
  rm -f "$TMP_RPM"
  echo "✅ VS Code installed."
}

config() {
  echo "⚙️  [$MODULE_NAME] No extra VS Code config yet (using package defaults)."
}

clean() {
  echo "🧹 [$MODULE_NAME] Removing VS Code RPM…"
  sudo dnf remove -y code || true
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


