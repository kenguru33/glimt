#!/bin/bash
# modules/fedora/install-docker.sh
# Glimt module: Install Docker CE (rootful/system daemon mode)
# - Installs Docker engine and CLI from Docker's official repository
# - Enables and starts the Docker system service
# - Adds current user to docker group for non-sudo access
# - Pattern: all | deps | install | config | clean

set -euo pipefail
trap 'echo "❌ docker: error on line $LINENO" >&2' ERR

MODULE_NAME="docker"
ACTION="${1:-all}"

# === Real user context ====================================================
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

# === Fedora-only guard ====================================================
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || {
    echo "❌ Fedora/RHEL-based systems only."
    exit 1
  }
else
  echo "❌ Cannot detect OS."
  exit 1
fi

ARCH="$(uname -m)"
KEYRING="/etc/pki/rpm-gpg/docker.gpg"
REPO_FILE="/etc/yum.repos.d/docker-ce.repo"

# --- Helpers --------------------------------------------------------------

deps() {
  echo "📦 Installing prerequisites…"
  sudo dnf makecache -y
  sudo dnf install -y curl gnupg2 dnf-plugins-core
}

ensure_repo() {
  echo "🏷️  Ensuring Docker DNF repository…"
  if [[ ! -f "$REPO_FILE" ]]; then
    # Import GPG key
    if [[ ! -f "$KEYRING" ]]; then
      sudo install -m0755 -d "$(dirname "$KEYRING")"
      curl -fsSL https://download.docker.com/linux/fedora/gpg | sudo gpg --dearmor -o "$KEYRING"
      sudo chmod a+r "$KEYRING"
    fi
    
    # Add repository
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo || {
      # Fallback: create repo file manually
      sudo tee "$REPO_FILE" >/dev/null <<EOF
[docker-ce-stable]
name=Docker CE Stable - \$basearch
baseurl=https://download.docker.com/linux/fedora/\$releasever/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=file://$KEYRING
EOF
    }
  fi
  sudo dnf makecache -y
}

remove_conflicts() {
  # Remove any conflicting packages
  if rpm -q docker >/dev/null 2>&1; then
    echo "🧹 Removing conflicting package: docker"
    sudo dnf remove -y docker || true
  fi
  if rpm -q docker-engine >/dev/null 2>&1; then
    echo "🧹 Removing conflicting package: docker-engine"
    sudo dnf remove -y docker-engine || true
  fi
}

install_docker() {
  echo "🐳 Installing Docker engine + CLI…"
  sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

add_user_to_docker_group() {
  echo "👤 Adding $REAL_USER to docker group…"
  if ! groups "$REAL_USER" | grep -q docker; then
    sudo usermod -aG docker "$REAL_USER"
    echo "✅ User $REAL_USER added to docker group."
    echo "ℹ️  You may need to log out and back in for group changes to take effect."
  else
    echo "ℹ️  User $REAL_USER is already in docker group."
  fi
}

enable_and_start_docker() {
  echo "🚀 Enabling and starting Docker service…"
  sudo systemctl enable docker
  sudo systemctl start docker
  echo "✅ Docker service enabled and started."
}

verify_installation() {
  echo "🔍 Verifying Docker installation…"
  if sudo docker info >/dev/null 2>&1; then
    echo "✅ Docker is running correctly."
    sudo docker --version
  else
    echo "❌ Docker is not running correctly."
    return 1
  fi
}

# --- Actions -------------------------------------------------------------

install() {
  deps
  ensure_repo
  remove_conflicts
  install_docker
  add_user_to_docker_group
  enable_and_start_docker
  verify_installation
}

config() {
  add_user_to_docker_group
  enable_and_start_docker
  verify_installation
}

clean() {
  echo "🧹 Stopping and disabling Docker service…"
  sudo systemctl stop docker || true
  sudo systemctl disable docker || true
  
  echo "🧹 Removing user from docker group…"
  sudo gpasswd -d "$REAL_USER" docker 2>/dev/null || true
  
  echo "🗑 Optional package removal (manual):"
  echo "    sudo dnf remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
  echo "    sudo rm -f $REPO_FILE $KEYRING"
}

case "$ACTION" in
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
all)
  deps
  install
  config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac

