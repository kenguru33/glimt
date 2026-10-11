#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="gh"
ACTION="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

COMPLETION_DIR="$HOME_DIR/.zsh/plugins/gh"
COMPLETION_FILE="$COMPLETION_DIR/_gh"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
TEMPLATE_FILE="$SCRIPT_DIR/config/gh.zsh"
TARGET_FILE="$ZSH_CONFIG_DIR/gh.zsh"

# === Step: deps ===
deps() {
  log "Installing gh..."
  sudo dnf install -y gh
}

# === Step: install ===
install() {
  log "gh is installed via DNF — nothing else needed."
  verify_binary gh --version
}

# === Step: config ===
config() {
  log "Generating zsh completion..."
  run_as_user mkdir -p "$COMPLETION_DIR"
  # The redirect must happen in the user's shell, not the caller's (root)
  # shellcheck disable=SC2016  # $1 is expanded by the inner sh
  run_as_user sh -c 'gh completion -s zsh > "$1"' _ "$COMPLETION_FILE"

  deploy_config "$TEMPLATE_FILE" "$TARGET_FILE"
}

# === Step: clean ===
clean() {
  log "Cleaning gh setup..."
  rm -f "$TARGET_FILE"
  rm -rf "$COMPLETION_DIR"

  if confirm "Uninstall gh package as well?"; then
    sudo dnf remove -y gh
    log "gh package removed."
  fi
}

# === Entry point ===
case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
