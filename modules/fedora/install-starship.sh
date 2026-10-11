#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="starship"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

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
  run_as_user mkdir -p "$LOCAL_BIN"
  if [[ ! -x "$LOCAL_BIN/starship" ]]; then
    # Download as the caller, but run the installer as the user so the binary
    # in ~/.local/bin is owned by them (always tracks the latest release)
    curl -fsSL https://starship.rs/install.sh | run_as_user sh -s -- -y --bin-dir "$LOCAL_BIN"
    echo "✅ Starship installed to $LOCAL_BIN"
  else
    echo "⏭️  Starship already installed"
  fi
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

