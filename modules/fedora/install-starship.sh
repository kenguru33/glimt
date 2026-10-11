#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

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
  echo "Checking dependencies for Starship..."
  if ! command -v curl >/dev/null; then
    echo "Installing curl..."
    dnf_ensure curl
  fi
}

# Latest release version without the leading "v" (empty when unreachable)
latest_release_version() {
  curl -fsSL https://api.github.com/repos/starship/starship/releases/latest 2>/dev/null |
    sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -n1 || true
}

# === Step: install ===
install() {
  echo "Installing Starship..."
  run_as_user mkdir -p "$LOCAL_BIN"
  # Tracks the latest release: skip when the installed binary already is it
  # (or when the latest version can't be resolved and one is installed)
  local latest current=""
  latest="$(latest_release_version)"
  if [[ -x "$LOCAL_BIN/starship" ]]; then
    current="$("$LOCAL_BIN/starship" --version 2>/dev/null | awk 'NR == 1 {print $2}' || true)"
  fi
  if [[ -n "$current" && ( -z "$latest" || "$current" == "$latest" ) ]]; then
    echo "starship $current is up to date"
  else
    [[ -n "$current" ]] && echo "Updating starship $current to $latest..."
    # Download as the caller, but run the installer as the user so the binary
    # in ~/.local/bin is owned by them (always tracks the latest release)
    curl -fsSL https://starship.rs/install.sh | run_as_user sh -s -- -y --bin-dir "$LOCAL_BIN"
    echo "Starship installed to $LOCAL_BIN"
  fi
  verify_binary starship --version
}

# === Step: config ===
config() {
  echo "Installing starship.zsh config from template..."

  deploy_config "$TEMPLATE_FILE" "$TARGET_FILE"
  echo "Installed $TARGET_FILE"
}

# === Step: clean ===
clean() {
  echo "Cleaning Starship setup..."

  echo "Removing starship binary"
  rm -f "$LOCAL_BIN/starship"

  echo "Removing starship.zsh config"
  rm -f "$TARGET_FILE"

  echo "Clean complete."
}

# === Entry Point ===
case "$ACTION" in
  all)    deps; install; config ;;
  deps)   deps ;;
  install) install ;;
  config) config ;;
  clean)  clean ;;
  *)
    echo "[$MODULE_NAME] unknown action: $ACTION" >&2
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

