#!/bin/bash
set -e
trap 'echo "❌ Neovim setup failed. Exiting." >&2' ERR

MODULE_NAME="nvim"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/nvim.zsh"
TARGET_FILE="$CONFIG_DIR/nvim.zsh"

# === Step: deps ===
deps() {
  echo "📦 Installing Neovim via dnf..."
  sudo dnf makecache -y
  sudo dnf install -y neovim
}

# === Step: install ===
install() {
  echo "✅ Neovim is installed system-wide. Nothing to install here."
}

# === Step: config ===
config() {
  echo "📝 Installing nvim.zsh config from template..."

  mkdir -p "$CONFIG_DIR"
  cp "$TEMPLATE_FILE" "$TARGET_FILE"
  chown "$REAL_USER:$REAL_USER" "$TARGET_FILE"
  echo "✅ Installed $TARGET_FILE"
}

# === Step: clean ===
clean() {
  echo "🧹 Removing Neovim config..."

  rm -f "$TARGET_FILE"
  echo "✅ Removed $TARGET_FILE"
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

