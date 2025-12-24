#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="dotnet10"
ACTION="${1:-all}"

# === OS detection ===
[[ -f /etc/os-release ]] || {
  echo "❌ /etc/os-release missing"
  exit 1
}
. /etc/os-release
[[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || {
  echo "❌ Debian-based only"
  exit 1
}

# Map Debian series for Microsoft repo payload
# Microsoft often lags publishing a new series; 12 config works on 13.
case "${VERSION_ID:-}" in
13) MS_SERIES=12 ;; # Trixie -> use debian/12 config if 13 isn't available
12) MS_SERIES=12 ;;
11) MS_SERIES=11 ;;
*) MS_SERIES=12 ;; # reasonable default
esac

DEPS=(wget gpg apt-transport-https)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo apt update
  sudo apt install -y "${DEPS[@]}"
}

add_ms_repo() {
  local deb="/tmp/packages-microsoft-prod.deb"
  local url="https://packages.microsoft.com/config/debian/${MS_SERIES}/packages-microsoft-prod.deb"

  # Skip if already installed
  if dpkg -s packages-microsoft-prod >/dev/null 2>&1; then
    echo "ℹ️ Microsoft repo already present."
    return 0
  fi

  echo "🔑 Adding Microsoft repo (debian/${MS_SERIES})..."
  wget -qO "$deb" "$url"
  sudo dpkg -i "$deb"
  rm -f "$deb"
  sudo apt update
}

install_dotnet() {
  add_ms_repo
  echo "📦 Installing .NET 10 SDK + runtimes..."
  sudo apt install -y dotnet-sdk-10.0 aspnetcore-runtime-10.0 dotnet-runtime-10.0
}

config_dotnet() {
  echo "⚙️ Verifying .NET installation..."
  command -v dotnet >/dev/null 2>&1 || {
    echo "❌ 'dotnet' not found"
    exit 1
  }
  dotnet --list-sdks | grep -E '^10\.' >/dev/null 2>&1 &&
    echo "✅ .NET 10 SDK detected:" &&
    dotnet --list-sdks | grep -E '^10\.' ||
    echo "⚠️ .NET 10 SDK not listed. Check packages."
}

clean_dotnet() {
  echo "🧹 Removing .NET 10 SDK & runtimes..."
  sudo apt remove --purge -y dotnet-sdk-10.0 aspnetcore-runtime-10.0 dotnet-runtime-10.0 || true
  sudo apt autoremove -y
  # Keep packages-microsoft-prod because you might use it for other tooling;
  # uncomment the next two lines to remove it as well.
  # sudo apt remove --purge -y packages-microsoft-prod || true
  # sudo rm -f /etc/apt/sources.list.d/microsoft-prod.list /etc/apt/trusted.gpg.d/microsoft.gpg || true
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


