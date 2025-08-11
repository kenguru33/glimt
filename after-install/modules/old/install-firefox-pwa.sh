#!/bin/bash
set -e

MODULE_NAME="firefoxpwa"
ACTION="${1:-all}"
OS_ID=""

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Could not detect operating system."
  exit 1
fi

# === Dependencies ===
DEPS_DEBIAN=(debian-archive-keyring curl gpg apt-transport-https)
DEPS_FEDORA=(curl gpg)

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

install_firefoxpwa() {
  echo "🦊 Installing FirefoxPWA..."

  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
    echo "🔑 Importing GPG key..."
    curl -fsSL https://packagecloud.io/filips/FirefoxPWA/gpgkey | \
      gpg --dearmor | \
      sudo tee /usr/share/keyrings/firefoxpwa-keyring.gpg > /dev/null

    echo "➕ Adding APT source..."
    echo "deb [signed-by=/usr/share/keyrings/firefoxpwa-keyring.gpg] https://packagecloud.io/filips/FirefoxPWA/any any main" | \
      sudo tee /etc/apt/sources.list.d/firefoxpwa.list > /dev/null

    echo "🔄 Updating repositories..."
    sudo apt update

    echo "📦 Installing FirefoxPWA package..."
    sudo apt install -y firefoxpwa

  elif [[ "$OS_ID" == "fedora" ]]; then
    echo "🔑 Importing GPG key..."
    sudo rpm --import https://packagecloud.io/filips/FirefoxPWA/gpgkey

    echo "➕ Adding repo file..."
    sudo tee /etc/yum.repos.d/firefoxpwa.repo > /dev/null <<EOF
[firefoxpwa]
name=FirefoxPWA
metadata_expire=7d
baseurl=https://packagecloud.io/filips/FirefoxPWA/rpm_any/rpm_any/\$basearch
gpgkey=https://packagecloud.io/filips/FirefoxPWA/gpgkey
repo_gpgcheck=1
gpgcheck=0
enabled=1
EOF

    echo "🔄 Updating DNF cache..."
    sudo dnf -q makecache -y --disablerepo="*" --enablerepo="firefoxpwa"

    echo "📦 Installing FirefoxPWA..."
    sudo dnf install -y firefoxpwa
  else
    echo "❌ Unsupported OS: $OS_ID"
    exit 1
  fi

  echo "✅ FirefoxPWA installed."

  echo
  echo "🌐 To complete the setup, install the Firefox extension:"
  echo "🔗 https://addons.mozilla.org/firefox/addon/pwas-for-firefox/"
  echo

}

config_firefoxpwa() {
  echo "⚙️ No additional configuration needed for FirefoxPWA."
}

clean_firefoxpwa() {
  echo "🧹 Removing FirefoxPWA..."

  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
    sudo apt purge -y firefoxpwa || true
    sudo apt autoremove -y
    sudo rm -f /usr/share/keyrings/firefoxpwa-keyring.gpg
    sudo rm -f /etc/apt/sources.list.d/firefoxpwa.list
  elif [[ "$OS_ID" == "fedora" ]]; then
    sudo dnf remove -y firefoxpwa || true
    sudo rm -f /etc/yum.repos.d/firefoxpwa.repo
  fi

  echo "✅ FirefoxPWA removed."
}

# === Entry point ===
case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_firefoxpwa
    ;;
  config)
    config_firefoxpwa
    ;;
  clean)
    clean_firefoxpwa
    ;;
  all)
    install_deps
    install_firefoxpwa
    config_firefoxpwa
    ;;
  *)
    echo "Usage: $0 {deps|install|config|clean|all}"
    exit 1
    ;;
esac
