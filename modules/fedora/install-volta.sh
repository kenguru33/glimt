#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

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
  echo "Error: Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "Error: This module supports Fedora/RHEL-based systems only."
  exit 1
fi

# === Step: deps ===
deps() {
  echo "Checking for curl..."

  if ! command -v curl >/dev/null; then
    echo "Installing curl via dnf..."
    dnf_ensure curl
  fi
}

# Latest release version without the leading "v" (empty when unreachable)
latest_release_version() {
  curl -fsSL https://api.github.com/repos/volta-cli/volta/releases/latest 2>/dev/null |
    sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1 || true
}

# === Step: install ===
install() {
  echo "⬇️ Installing Volta for user $REAL_USER..."

  # Tracks the latest release: skip when the installed binary already is it
  # (or when the latest version can't be resolved and one is installed)
  local latest current=""
  latest="$(latest_release_version)"
  if [[ -x "$VOLTA_BIN" ]]; then
    current="$("$VOLTA_BIN" --version 2>/dev/null || true)"
  fi
  if [[ -n "$current" && ( -z "$latest" || "$current" == "$latest" ) ]]; then
    echo "volta $current is up to date"
  else
    [[ -n "$current" ]] && echo "Updating volta $current to $latest..."
    # Run the installer itself as the user (not the caller) so ~/.volta is theirs
    curl -fsSL https://get.volta.sh | run_as_user env VOLTA_HOME="$VOLTA_HOME_DIR" bash -s -- --skip-setup
    echo "Volta installed to ~/.volta"
  fi

  verify_binary "$VOLTA_BIN" --version

  echo "⬇️ Installing latest Node.js via Volta..."
  run_as_user env VOLTA_HOME="$VOLTA_HOME_DIR" PATH="$VOLTA_HOME_DIR/bin:$PATH" \
    "$VOLTA_BIN" install node
  echo "Node.js installed via Volta"
}

# === Step: config ===
config() {
  echo "Installing volta.zsh config from template..."

  deploy_config "$TEMPLATE_FILE" "$TARGET_FILE"
  echo "Installed $TARGET_FILE"
}

# === Step: clean ===
clean() {
  echo "Cleaning Volta setup..."

  echo "Removing ~/.volta"
  sudo -u "$REAL_USER" rm -rf "$HOME_DIR/.volta"

  echo "Removing volta.zsh config"
  sudo -u "$REAL_USER" rm -f "$TARGET_FILE"

  echo "Clean complete."
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
  echo "[$MODULE_NAME] unknown action: $ACTION" >&2
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac


