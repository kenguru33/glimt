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

# === Debian/Trixie ===
install_debian_nonfree() {
  echo "🔧 Backing up /etc/apt/sources.list..."
  sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak

  echo "📝 Enabling contrib and non-free-firmware..."
  sudo sed -i -E 's/^deb (.*) (trixie[^ ]*) main(.*)$/deb \1 \2 main contrib non-free-firmware/' /etc/apt/sources.list

  echo "🔄 Updating APT sources..."
  sudo apt update

  echo "📦 Installing firmware packages..."
  sudo apt install -y firmware-linux firmware-misc-nonfree
}

clean_debian_nonfree() {
  echo "🧹 Restoring original /etc/apt/sources.list..."
  if [[ -f /etc/apt/sources.list.bak ]]; then
    sudo cp /etc/apt/sources.list.bak /etc/apt/sources.list
    sudo apt update
  else
    echo "⚠️ No backup found at /etc/apt/sources.list.bak"
  fi
}

# === Fedora ===
install_fedora_rpmfusion() {
  echo "📦 Adding RPM Fusion repos..."

  sudo dnf install -y \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-"$(rpm -E %fedora)".noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-"$(rpm -E %fedora)".noarch.rpm

  echo "✅ RPM Fusion enabled."
}

clean_fedora_rpmfusion() {
  echo "🧹 Removing RPM Fusion repositories..."
  sudo dnf remove -y rpmfusion-free-release\* rpmfusion-nonfree-release\*
  echo "✅ RPM Fusion repos removed."
}

# === Dispatcher ===
case "$ACTION" in
  all | install)
    if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
      install_debian_nonfree
    elif [[ "$OS_ID" == "fedora" ]]; then
      install_fedora_rpmfusion
    else
      echo "❌ Unsupported OS: $OS_ID"
      exit 1
    fi
    ;;
  config)
    echo "ℹ️ No additional config required for this module."
    ;;
  clean)
    if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
      clean_debian_nonfree
    elif [[ "$OS_ID" == "fedora" ]]; then
      clean_fedora_rpmfusion
    else
      echo "❌ Unsupported OS: $OS_ID"
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 [all|install|config|clean]"
    exit 1
    ;;
esac
