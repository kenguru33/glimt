#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Eza install failed. Exiting." >&2' ERR

MODULE_NAME="eza"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"
CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/eza.zsh"
TARGET_FILE="$CONFIG_DIR/eza.zsh"

# === Step: deps ===
deps() {
  echo "📦 Installing eza..."
  
  # Check if eza is already installed
  if command -v eza &>/dev/null; then
    echo "✅ eza is already installed."
    return
  fi
  
  # Try Fedora repos first
  if sudo dnf install -y eza 2>/dev/null; then
    echo "✅ eza installed from Fedora repos."
    return
  fi
  
  # Fallback: Enable COPR repository and install
  echo "⚠️  eza not available in Fedora repos. Enabling COPR repository..."
  
  # Install dnf-plugins-core if not present (needed for copr)
  if ! rpm -q dnf-plugins-core &>/dev/null; then
    echo "📦 Installing dnf-plugins-core..."
    sudo dnf install -y dnf-plugins-core
  fi
  
  # Enable dturner/eza COPR repository
  echo "🔧 Enabling dturner/eza COPR repository..."
  if sudo dnf copr enable -y dturner/eza; then
    echo "✅ COPR repository enabled."
  else
    echo "❌ Failed to enable COPR repository."
    exit 1
  fi
  
  # Install eza from COPR
  echo "📦 Installing eza from COPR repository..."
  if sudo dnf install -y eza; then
    echo "✅ eza installed from COPR repository."
  else
    echo "❌ Failed to install eza from COPR repository."
    exit 1
  fi
}

# === Step: install ===
install() {
  echo "ℹ️  eza is installed via DNF. Nothing else needed."
}

# === Step: config ===
config() {
  echo "📝 Writing eza.zsh config from template..."

  deploy_config "$TEMPLATE_FILE" "$TARGET_FILE"

  echo "✅ Installed $TARGET_FILE"
}

# === Step: clean ===
clean() {
  echo "🧹 Cleaning eza setup..."

  echo "❌ Removing eza.zsh config"
  rm -f "$TARGET_FILE"

  read -rp "Uninstall eza package as well? [y/N]: " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sudo dnf remove -y eza
    echo "✅ eza package removed."
  fi
}

# === Entry Point ===
case "$ACTION" in
  all)    deps; install; config ;;
  deps)   deps ;;
  install) install ;;
  config) config ;;
  clean)  clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

