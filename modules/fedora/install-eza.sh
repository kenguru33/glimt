#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="eza"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/eza.zsh"
TARGET_FILE="$CONFIG_DIR/eza.zsh"

# === Step: deps ===
deps() {
  echo "Installing eza..."
  
  # Already installed from a repo: upgrade it (no-op when current)
  if rpm -q eza &>/dev/null; then
    echo "eza is already installed, checking for updates..."
    sudo dnf upgrade -y eza
    return
  fi

  # Installed some other way (cargo, manual binary): leave it alone
  if command -v eza &>/dev/null; then
    echo "eza is already installed."
    return
  fi
  
  # Try Fedora repos first
  if sudo dnf install -y eza 2>/dev/null; then
    echo "eza installed from Fedora repos."
    return
  fi
  
  # Fallback: Enable COPR repository and install
  echo "Warning: eza not available in Fedora repos. Enabling COPR repository..."
  
  # Install dnf-plugins-core if not present (needed for copr)
  dnf_ensure dnf-plugins-core
  
  # Enable dturner/eza COPR repository
  echo "Enabling dturner/eza COPR repository..."
  if sudo dnf copr enable -y dturner/eza; then
    echo "COPR repository enabled."
  else
    echo "Error: Failed to enable COPR repository."
    exit 1
  fi
  
  # Install eza from COPR
  echo "Installing eza from COPR repository..."
  if sudo dnf install -y eza; then
    echo "eza installed from COPR repository."
  else
    echo "Error: Failed to install eza from COPR repository."
    exit 1
  fi
}

# === Step: install ===
install() {
  echo "ℹ️  eza is installed via DNF. Nothing else needed."
}

# === Step: config ===
config() {
  echo "Writing eza.zsh config from template..."

  deploy_config "$TEMPLATE_FILE" "$TARGET_FILE"

  echo "Installed $TARGET_FILE"
}

# === Step: clean ===
clean() {
  echo "Cleaning eza setup..."

  echo "Removing eza.zsh config"
  rm -f "$TARGET_FILE"

  if confirm "Uninstall eza package as well?"; then
    sudo dnf remove -y eza
    echo "eza package removed."
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
    echo "[$MODULE_NAME] unknown action: $ACTION" >&2
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

