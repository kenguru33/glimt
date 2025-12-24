#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="dotnet8"
ACTION="${1:-all}"

# === OS detection ===
[[ -f /etc/os-release ]] || {
  echo "❌ /etc/os-release missing"
  exit 1
}
. /etc/os-release
[[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || {
  echo "❌ Fedora/RHEL-based systems only"
  exit 1
}

DEPS=(wget gpg)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y "${DEPS[@]}"
}

add_ms_repo() {
  local rpm="/tmp/packages-microsoft-prod.rpm"
  local url="https://packages.microsoft.com/config/fedora/$(rpm -E %fedora)/packages-microsoft-prod.rpm"

  # Skip if already installed
  if rpm -q packages-microsoft-prod >/dev/null 2>&1; then
    echo "ℹ️ Microsoft repo already present."
    return 0
  fi

  echo "🔑 Adding Microsoft repo (fedora/$(rpm -E %fedora))..."
  wget -qO "$rpm" "$url" || curl -fsSL "$url" -o "$rpm"
  sudo rpm -i "$rpm"
  rm -f "$rpm"
  sudo dnf makecache -y
}

install_dotnet() {
  add_ms_repo
  echo "📦 Installing .NET 8 SDK + runtimes..."
  sudo dnf install -y dotnet-sdk-8.0 aspnetcore-runtime-8.0 dotnet-runtime-8.0
}

config_dotnet() {
  echo "⚙️ Verifying installation..."
  if ! command -v dotnet >/dev/null 2>&1; then
    echo "❌ 'dotnet' not found after install"
    exit 1
  fi
  dotnet --list-sdks | grep -E '^8\.' >/dev/null 2>&1 &&
    echo "✅ .NET 8 SDK detected:" &&
    dotnet --list-sdks | grep -E '^8\.' ||
    echo "⚠️ .NET 8 SDK not listed. Check packages."
}

clean_dotnet() {
  echo "🧹 Removing .NET 8 SDK & runtimes..."
  sudo dnf remove -y dotnet-sdk-8.0 aspnetcore-runtime-8.0 dotnet-runtime-8.0 || true
  # Keep packages-microsoft-prod because you might use it for other tooling;
  # uncomment the next two lines to remove it as well.
  # sudo dnf remove -y packages-microsoft-prod || true
  # sudo rm -f /etc/yum.repos.d/microsoft-prod.repo /etc/pki/rpm-gpg/microsoft-prod.gpg || true
}

case "$ACTION" in
deps) install_deps ;;
install) install_dotnet ;;
config) config_dotnet ;;
clean) clean_dotnet ;;
all)
  install_deps
  install_dotnet
  config_dotnet
  ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac


