#!/bin/bash
set -e

MODULE_NAME="1password"
ACTION="${1:-all}"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Unable to detect OS."
  exit 1
fi

# === Constants ===
DEBIAN_KEYRING="/usr/share/keyrings/1password-archive-keyring.gpg"
DEBIAN_SOURCE="/etc/apt/sources.list.d/1password.list"
FEDORA_REPO="/etc/yum.repos.d/1password.repo"
FEDORA_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-1Password"

DEPS_DEBIAN=(curl gnupg apt-transport-https)
DEPS_FEDORA=(curl gnupg2)

# === Dependency Installer ===
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

# === Install ===
install_1password() {
  echo "🔐 Installing 1Password for $OS_ID..."

  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
    echo "🔑 Importing GPG key..."
    sudo rm -f "$DEBIAN_KEYRING"
    curl -sS https://downloads.1password.com/linux/keys/1password.asc \
      | sudo gpg --dearmor --output "$DEBIAN_KEYRING"

    echo "➕ Adding APT repo..."
    echo "deb [arch=amd64 signed-by=$DEBIAN_KEYRING] https://downloads.1password.com/linux/debian/amd64 stable main" \
      | sudo tee "$DEBIAN_SOURCE" > /dev/null

    echo "📦 Installing 1Password..."
    sudo apt update
    sudo apt install -y 1password

  elif [[ "$OS_ID" == "fedora" ]]; then
    echo "🔑 Importing GPG key..."
    sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc

    echo "📁 Adding DNF repo..."
    sudo tee "$FEDORA_REPO" > /dev/null <<EOF
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

    echo "📦 Installing 1Password (forced, non-interactive)..."
    sudo dnf install -y --nogpgcheck 1password
  else
    echo "❌ Unsupported OS: $OS_ID"
    exit 1
  fi

  echo "✅ 1Password installed."
}

# === Clean ===
clean_1password() {
  echo "🧹 Removing 1Password..."

  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
    sudo apt purge -y 1password || true
    sudo rm -f "$DEBIAN_SOURCE" "$DEBIAN_KEYRING"
    sudo apt update
  elif [[ "$OS_ID" == "fedora" ]]; then
    sudo dnf remove -y 1password || true
    sudo rm -f "$FEDORA_REPO"
  else
    echo "❌ Unsupported OS: $OS_ID"
    exit 1
  fi

  echo "✅ Clean complete."
}

# === Main Dispatcher ===
case "$ACTION" in
  deps)    install_deps ;;
  install) install_1password ;;
  clean)   clean_1password ;;
  all)
    install_deps
    install_1password
    ;;
  *)
    echo "Usage: $0 [deps|install|clean|all]"
    exit 1
    ;;
esac
