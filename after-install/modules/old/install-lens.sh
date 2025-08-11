#!/bin/bash
set -e

MODULE_NAME="lens"
ACTION="${1:-all}"

APT_SOURCE="/etc/apt/sources.list.d/lens.list"
KEYRING="/usr/share/keyrings/lens-archive-keyring.gpg"
REPO_FILE="/etc/yum.repos.d/lens.repo"

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Could not detect operating system."
  exit 1
fi

# === Dependencies ===
DEPS_DEBIAN=(curl gnupg apt-transport-https)
DEPS_FEDORA=(curl gnupg2 dnf-plugins-core)

install_deps() {
  echo "📦 Installing dependencies for $OS_ID..."
  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
    sudo apt update
    sudo apt install -y "${DEPS_DEBIAN[@]}"
  elif [[ "$OS_ID" == "fedora" ]]; then
    sudo dnf install -y "${DEPS_FEDORA[@]}"
  else
    echo "❌ Unsupported OS: $OS_ID"
    exit 1
  fi
}

install_lens() {
  echo "📦 Installing Lens Desktop..."

  if command -v lens &>/dev/null; then
    echo "✅ Lens is already installed."
    return
  fi

  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
    echo "🔑 Adding GPG key..."
    curl -fsSL https://downloads.k8slens.dev/keys/gpg | gpg --dearmor | sudo tee "$KEYRING" > /dev/null

    echo "📁 Adding APT source..."
    echo "deb [arch=amd64 signed-by=$KEYRING] https://downloads.k8slens.dev/apt/debian stable main" \
      | sudo tee "$APT_SOURCE" > /dev/null

    echo "🔄 Updating package lists..."
    sudo apt update

    echo "⬇️ Installing Lens..."
    sudo apt install -y lens

  elif [[ "$OS_ID" == "fedora" ]]; then
    echo "📁 Adding DNF repo manually..."
    sudo curl -fsSL -o "$REPO_FILE" https://downloads.k8slens.dev/rpm/lens.repo

    echo "🔄 Refreshing repo cache..."
    sudo dnf makecache --refresh

    echo "⬇️ Installing Lens..."
    sudo dnf install -y lens
  else
    echo "❌ Unsupported OS: $OS_ID"
    exit 1
  fi

  echo "✅ Lens Desktop installed."
}

clean_lens() {
  echo "🧹 Removing Lens Desktop..."

  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
    sudo apt remove -y lens || true
    sudo rm -f "$APT_SOURCE" "$KEYRING"
    sudo apt update

  elif [[ "$OS_ID" == "fedora" ]]; then
    sudo dnf remove -y lens || true
    sudo rm -f "$REPO_FILE"
    sudo dnf clean all
  fi

  echo "✅ Lens Desktop removed."
}

# === Entry point ===
case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_lens
    ;;
  clean)
    clean_lens
    ;;
  all)
    install_deps
    install_lens
    ;;
  *)
    echo "Usage: $0 [deps|install|clean|all]"
    exit 1
    ;;
esac
