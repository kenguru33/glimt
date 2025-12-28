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

# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------
ensure_testing_available() {
  if ! apt-cache policy | grep -q "testing"; then
    echo "❌ Debian testing repository not available."
    echo "👉 Run your enable-nonfree.sh cherry-pick first."
    exit 1
  fi
}

# ---------------------------------------------------------
# deps
# ---------------------------------------------------------
deps() {
  echo "📦 Installing Neovim from Debian testing (cherry-pick)..."

  ensure_testing_available

  sudo apt update
  sudo apt install -y -t testing neovim

  echo "✅ Neovim installed from testing"
}

# ---------------------------------------------------------
# install
# ---------------------------------------------------------
install() {
  echo "ℹ️ Neovim is installed via apt. Nothing else to install."
}

# ---------------------------------------------------------
# config
# ---------------------------------------------------------
config() {
  echo "📝 Installing nvim.zsh config from template..."

  mkdir -p "$CONFIG_DIR"
  cp "$TEMPLATE_FILE" "$TARGET_FILE"
  chown "$REAL_USER:$REAL_USER" "$TARGET_FILE"

  echo "✅ Installed $TARGET_FILE"
}

# ---------------------------------------------------------
# clean
# ---------------------------------------------------------
clean() {
  echo "🧹 Removing Neovim config..."

  rm -f "$TARGET_FILE"
  echo "✅ Removed $TARGET_FILE"

  echo "ℹ️ Neovim package not removed automatically."
}

# ---------------------------------------------------------
# entrypoint
# ---------------------------------------------------------
case "$ACTION" in
all)
  deps
  install
  config
  ;;
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  echo "❌ Unknown action: $ACTION"
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
