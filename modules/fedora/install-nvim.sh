#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Neovim setup failed. Exiting." >&2' ERR

MODULE_NAME="nvim"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"
CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/nvim.zsh"
TARGET_FILE="$CONFIG_DIR/nvim.zsh"

# === Step: deps ===
deps() {
  echo "📦 Installing Neovim via dnf..."
  sudo dnf install -y neovim
  verify_binary nvim --version
}

# === Step: install ===
install() {
  echo "✅ Neovim is installed system-wide. Nothing to install here."
}

# === Step: config ===
config() {
  echo "📝 Installing nvim.zsh config from template..."

  deploy_config "$TEMPLATE_FILE" "$TARGET_FILE"
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

