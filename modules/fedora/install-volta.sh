#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="volta"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/volta.zsh"
TARGET_FILE="$CONFIG_DIR/volta.zsh"
VOLTA_HOME_DIR="$HOME_DIR/.volta"
VOLTA_BIN="$VOLTA_HOME_DIR/bin/volta"

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
    sudo dnf install -y curl
  fi
}

# === Step: install ===
install() {
  echo "⬇️ Installing Volta for user $REAL_USER..."

  if [[ ! -x "$VOLTA_BIN" ]]; then
    # Run the installer itself as the user (not the caller) so ~/.volta is theirs
    curl -fsSL https://get.volta.sh | run_as_user env VOLTA_HOME="$VOLTA_HOME_DIR" bash -s -- --skip-setup
    echo "✅ Volta installed to ~/.volta"
  else
    echo "⏭️  Volta already installed"
  fi

  verify_binary "$VOLTA_BIN" --version

  echo "⬇️ Installing latest Node.js via Volta..."
  run_as_user env VOLTA_HOME="$VOLTA_HOME_DIR" PATH="$VOLTA_HOME_DIR/bin:$PATH" \
    "$VOLTA_BIN" install node
  echo "✅ Node.js installed via Volta"
}

# === Step: config ===
config() {
  echo "📝 Installing volta.zsh config from template..."

  deploy_config "$TEMPLATE_FILE" "$TARGET_FILE"
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


