#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="dotnet9"
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
13) MS_SERIES=12 ;; # Trixie -> use debian/12 config
12) MS_SERIES=12 ;;
11) MS_SERIES=11 ;;
*) MS_SERIES=12 ;;
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

install_dotnet9() {
  add_ms_repo
  echo "📦 Installing .NET 9 SDK + runtimes..."
  sudo apt install -y dotnet-sdk-9.0 aspnetcore-runtime-9.0 dotnet-runtime-9.0
}

config_dotnet9() {
  echo "⚙️ Verifying .NET installation..."
  command -v dotnet >/dev/null 2>&1 || {
    echo "❌ 'dotnet' not found"
    exit 1
  }
  dotnet --list-sdks | grep -E '^9\.' >/dev/null 2>&1 &&
    echo "✅ .NET 9 SDK detected:" &&
    dotnet --list-sdks | grep -E '^9\.' ||
    echo "⚠️ .NET 9 SDK not listed. Check packages."
}

clean_dotnet9() {
  echo "🧹 Removing .NET 9..."
  sudo apt remove --purge -y dotnet-sdk-9.0 aspnetcore-runtime-9.0 dotnet-runtime-9.0 || true
  sudo apt autoremove -y
  # Keep packages-microsoft-prod for other tools; uncomment to remove it too:
  # sudo apt remove --purge -y packages-microsoft-prod || true
  # sudo rm -f /etc/apt/sources.list.d/microsoft-prod.list /etc/apt/trusted.gpg.d/microsoft.gpg || true
}

case "$ACTION" in
deps) install_deps ;;
install) install_dotnet9 ;;
config) config_dotnet9 ;;
clean) clean_dotnet9 ;;
all)
  install_deps
  install_dotnet9
  config_dotnet9
  ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
