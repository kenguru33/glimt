#!/bin/bash
set -e
trap 'echo "❌ Volta setup failed. Exiting." >&2' ERR

MODULE_NAME="volta"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/volta.zsh"
TARGET_FILE="$CONFIG_DIR/volta.zsh"
VOLTA_BIN="$HOME_DIR/.volta/bin/volta"
VOLTA_ENV="export VOLTA_HOME=\"$HOME_DIR/.volta\"; export PATH=\"\$VOLTA_HOME/bin:\$PATH\""

# === OS Check (Fedora only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This module supports Fedora/RHEL-based systems only."
  exit 1
fi

# === Step: deps ===
deps() {
  echo "📦 Checking for curl..."

  if ! command -v curl >/dev/null; then
    echo "➡️  Installing curl via dnf..."
    sudo dnf makecache -y
    sudo dnf install -y curl
  fi
}

# === Step: install ===
install() {
  echo "⬇️ Installing Volta for user $REAL_USER..."

  if [[ ! -x "$VOLTA_BIN" ]]; then
    sudo -u "$REAL_USER" curl https://get.volta.sh | bash -s -- --skip-setup
    echo "✅ Volta installed to ~/.volta"
  else
    echo "⏭️  Volta already installed"
  fi

  echo "⬇️ Installing latest Node.js via Volta..."
  sudo -u "$REAL_USER" env "$VOLTA_ENV" "$VOLTA_BIN" install node
  echo "✅ Node.js installed via Volta"
}

# === Step: config ===
config() {
  echo "📝 Installing volta.zsh config from template..."

  sudo -u "$REAL_USER" mkdir -p "$CONFIG_DIR"
  sudo -u "$REAL_USER" cp "$TEMPLATE_FILE" "$TARGET_FILE"
  chown "$REAL_USER:$REAL_USER" "$TARGET_FILE"
  echo "✅ Installed $TARGET_FILE"
}

# === Step: clean ===
clean() {
  echo "🧹 Cleaning Volta setup..."

  echo "❌ Removing ~/.volta"
  sudo -u "$REAL_USER" rm -rf "$HOME_DIR/.volta"

  echo "❌ Removing volta.zsh config"
  sudo -u "$REAL_USER" rm -f "$TARGET_FILE"

  echo "✅ Clean complete."
}

# === Entry Point ===
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


