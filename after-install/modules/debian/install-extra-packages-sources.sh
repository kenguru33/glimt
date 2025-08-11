#!/bin/bash
set -e

MODULE_NAME="enable-nonfree"
ACTION="${1:-all}"

# === Detect OS ===
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Cannot detect operating system."
  exit 1
fi

# === Ensure Debian ===
if [[ "$OS_ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
  echo "⚠️ This module only supports Debian. Skipping."
  exit 0
fi

SOURCES_FILE="/etc/apt/sources.list"

install_debian_nonfree() {
  echo "📝 Updating $SOURCES_FILE to enable contrib, non-free, and non-free-firmware..."

  sudo tee "$SOURCES_FILE" >/dev/null <<EOF
deb http://deb.debian.org/debian/ trixie main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie main contrib non-free

deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security trixie-security main contrib non-free

deb http://deb.debian.org/debian/ trixie-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ trixie-updates main contrib non-free
EOF

  if ! dpkg --print-foreign-architectures | grep -qx i386; then
    echo "🔧 Enabling i386 multiarch..."
    sudo dpkg --add-architecture i386
  fi

  echo "🔄 Updating APT sources..."
  sudo apt update

  echo "📦 Installing firmware packages..."
  sudo apt install -y firmware-linux firmware-misc-nonfree
}

clean_debian_nonfree() {
  echo "ℹ️ Clean does nothing — no backup kept by design."
}

# === Dispatcher ===
case "$ACTION" in
  all | install)
    install_debian_nonfree
    ;;
  config)
    echo "ℹ️ No additional config required for this module."
    ;;
  clean)
    clean_debian_nonfree
    ;;
  *)
    echo "Usage: $0 [all|install|config|clean]"
    exit 1
    ;;
esac
