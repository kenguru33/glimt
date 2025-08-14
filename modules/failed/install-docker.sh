#!/bin/bash
set -euo pipefail
trap 'echo "❌ Docker installation failed. Exiting." >&2' ERR

MODULE_NAME="docker"
ACTION="${1:-all}"

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || {
    echo "❌ This script only supports Debian or derivatives."
    exit 1
  }
else
  echo "❌ Cannot detect OS."
  exit 1
fi

# === Dependencies ===
DEPS=(ca-certificates curl gnupg lsb-release)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo apt update
  sudo apt install -y "${DEPS[@]}"
}

install_docker() {
  echo "🐳 Installing Docker Engine..."
  # Remove old versions if any
  sudo apt remove -y docker docker-engine docker.io containerd runc || true

  # Add Docker’s official GPG key
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  # Add Docker apt repo
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/debian $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

config_docker() {
  echo "⚙️ Configuring Docker..."
  # Add current user to docker group
  sudo usermod -aG docker "$USER"
  echo "ℹ️ You may need to log out and back in for group changes to apply."
}

clean_docker() {
  echo "🧹 Removing Docker and related configs..."
  sudo apt remove --purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo rm -f /etc/apt/sources.list.d/docker.list
  sudo rm -f /etc/apt/keyrings/docker.gpg
  sudo apt autoremove -y
}

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_docker
    ;;
  config)
    config_docker
    ;;
  clean)
    clean_docker
    ;;
  all)
    install_deps
    install_docker
    config_docker
    ;;
  *)
    echo "Usage: $0 {all|deps|install|config|clean}"
    exit 1
    ;;
esac
