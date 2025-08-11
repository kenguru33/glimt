#!/bin/bash
set -e
trap 'echo "❌ Eza install failed. Exiting." >&2' ERR

MODULE_NAME="eza"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/eza.zsh"
TARGET_FILE="$CONFIG_DIR/eza.zsh"

# === Step: deps ===
deps() {
  echo "📦 Installing eza..."
  sudo apt update
  sudo apt install -y eza
  echo "✅ eza installed."
}

# === Step: install ===
install() {
  echo "ℹ️  eza is installed via APT. Nothing else needed."
}

# === Step: config ===
config() {
  echo "📝 Writing eza.zsh config from template..."

  mkdir -p "$CONFIG_DIR"
  cp "$TEMPLATE_FILE" "$TARGET_FILE"
  chown "$REAL_USER:$REAL_USER" "$TARGET_FILE"

  echo "✅ Installed $TARGET_FILE"
}

# === Step: clean ===
clean() {
  echo "🧹 Cleaning eza setup..."

  echo "❌ Removing eza.zsh config"
  rm -f "$TARGET_FILE"

  read -rp "Uninstall eza package as well? [y/N]: " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sudo apt purge -y eza
    sudo apt autoremove -y
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
