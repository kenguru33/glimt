#!/bin/bash
set -e
trap 'echo "❌ kubectx module failed. Exiting." >&2' ERR

MODULE_NAME="kubectx"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/config/kubectx.zsh"
CONFIG_DEST="$HOME_DIR/.zsh/config/kubectx.zsh"

# === install ===
install() {
  echo "📦 Installing kubectx and kubens from Debian repo..."
  sudo apt update
  sudo apt install -y kubectx
  echo "✅ Installed kubectx and kubens"
}

# === config ===
config() {
  echo "⚙️  Copying Zsh config for kubectx..."

  if [[ ! -f "$CONFIG_SRC" ]]; then
    echo "❌ Config file not found: $CONFIG_SRC"
    exit 1
  fi

  mkdir -p "$(dirname "$CONFIG_DEST")"
  cp "$CONFIG_SRC" "$CONFIG_DEST"

  echo "✅ Config copied to $CONFIG_DEST"
}

# === clean ===
clean() {
  echo "🧹 Removing kubectx and related config..."
  sudo apt purge -y kubectx
  sudo apt autoremove -y
  rm -f "$CONFIG_DEST"
  echo "✅ Cleaned up"
}

# === all ===
all() {
  install
  config
}

# === entry point ===
case "$ACTION" in
  install) install ;;
  config) config ;;
  clean) clean ;;
  all) all ;;
  *)
    echo "Usage: $0 [all|install|config|clean]"
    exit 1
    ;;
esac
