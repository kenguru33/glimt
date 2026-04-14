#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Starship install failed. Exiting." >&2' ERR

MODULE_NAME="starship"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"
LOCAL_BIN="$HOME_DIR/.local/bin"
CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/starship.zsh"
TARGET_FILE="$CONFIG_DIR/starship.zsh"

# === Step: deps ===
deps() {
  echo "📦 Checking dependencies for Starship..."
  if ! command -v curl >/dev/null; then
    echo "📦 Installing curl..."
    sudo dnf install -y curl
  fi
}

# === Step: install ===
install() {
  echo "🚀 Installing Starship..."
  mkdir -p "$LOCAL_BIN"
  if [[ ! -x "$LOCAL_BIN/starship" ]]; then
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y --bin-dir "$LOCAL_BIN"
    echo "✅ Starship installed to $LOCAL_BIN"
  else
    echo "⏭️  Starship already installed"
  fi
  chown "$REAL_USER:$REAL_USER" "$LOCAL_BIN/starship"
  verify_binary starship --version
}

# === Step: config ===
config() {
  echo "📝 Installing starship.zsh config from template..."

  deploy_config "$TEMPLATE_FILE" "$TARGET_FILE"
  echo "✅ Installed $TARGET_FILE"
}

# === Step: clean ===
clean() {
  echo "🧹 Cleaning Starship setup..."

  echo "❌ Removing starship binary"
  rm -f "$LOCAL_BIN/starship"

  echo "❌ Removing starship.zsh config"
  rm -f "$TARGET_FILE"

  echo "✅ Clean complete."
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

