#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Volta setup failed. Exiting." >&2' ERR

MODULE_NAME="volta"
ACTION="${1:-all}"
HOME_DIR="$HOME"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME_DIR/.zsh/config"
TEMPLATE_FILE="$SCRIPT_DIR/config/volta.zsh"
TARGET_FILE="$CONFIG_DIR/volta.zsh"
VOLTA_BIN="$HOME_DIR/.volta/bin/volta"
VOLTA_ENV="export VOLTA_HOME=\"$HOME_DIR/.volta\"; export PATH=\"\$VOLTA_HOME/bin:\$PATH\""

require_user() {
  if [[ "$EUID" -eq 0 ]]; then
    echo "❌ Do not run this module as root." >&2
    exit 1
  fi
}

deps() {
  echo "📦 Ensuring curl is available (host side)..."
  if ! command -v curl >/dev/null 2>&1; then
    echo "⚠️  curl not found on host. Install curl first (e.g. rpm-ostree install curl) and re-run."
    exit 1
  fi
}

install() {
  require_user

  echo "⬇️ Installing Volta..."

  if [[ ! -x "$VOLTA_BIN" ]]; then
    # Run installer as the invoking (non-root) user
    curl https://get.volta.sh | bash -s -- --skip-setup
    echo "✅ Volta installed to ~/.volta"
  else
    echo "⏭️  Volta already installed"
  fi

  echo "⬇️ Installing latest Node.js via Volta..."
  env "$VOLTA_ENV" "$VOLTA_BIN" install node
  echo "✅ Node.js installed via Volta"
}

config() {
  require_user

  echo "📝 Installing volta.zsh config from template..."

  mkdir -p "$CONFIG_DIR"
  if [[ -f "$TEMPLATE_FILE" ]]; then
    cp "$TEMPLATE_FILE" "$TARGET_FILE"
    echo "✅ Installed $TARGET_FILE"
  else
    echo "⚠️  Template $TEMPLATE_FILE not found; skipping config copy."
  fi
}

clean() {
  require_user

  echo "🧹 Cleaning Volta setup..."

  echo "❌ Removing ~/.volta"
  rm -rf "$HOME_DIR/.volta"

  echo "❌ Removing volta.zsh config"
  rm -f "$TARGET_FILE"

  echo "✅ Clean complete."
}

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

