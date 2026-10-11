#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="k9s"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
K9S_CONFIG_DIR="$HOME_DIR/.config/k9s"
SKIN_DIR="$K9S_CONFIG_DIR/skins"
SKIN_FILE="catppuccin-mocha.yaml"
CONFIG_TEMPLATE="$SCRIPT_DIR/config/k9s-config.yaml"

deps() { log "No additional dependencies."; }

install() {
  brew_ensure k9s
  verify_binary k9s version
}

config() {
  mkdir -p "$SKIN_DIR"

  log "Downloading Catppuccin Mocha skin..."
  curl -fsSL "https://raw.githubusercontent.com/catppuccin/k9s/main/dist/$SKIN_FILE" \
    -o "$SKIN_DIR/$SKIN_FILE"

  deploy_config "$CONFIG_TEMPLATE" "$K9S_CONFIG_DIR/config.yaml"
  deploy_config "$SCRIPT_DIR/config/k9s.zsh" "$ZSH_CONFIG_DIR/k9s.zsh"
}

clean() {
  brew uninstall k9s 2>/dev/null || true
  # Only what config() deploys — keep other skins, plugins, aliases, etc.
  rm -f "${SKIN_DIR:?}/${SKIN_FILE:?}"
  # config.yaml: remove only while it is still glimt's template; a copy the
  # user has edited since is left in place
  if [[ -f "$K9S_CONFIG_DIR/config.yaml" ]]; then
    if cmp -s "$CONFIG_TEMPLATE" "$K9S_CONFIG_DIR/config.yaml"; then
      rm -f "${K9S_CONFIG_DIR:?}/config.yaml"
    else
      warn "Keeping $K9S_CONFIG_DIR/config.yaml (modified since glimt deployed it)"
    fi
  fi
  # Drop the directories only if nothing else lives there
  rmdir "$SKIN_DIR" 2>/dev/null || true
  rmdir "$K9S_CONFIG_DIR" 2>/dev/null || true
  rm -f "$ZSH_CONFIG_DIR/k9s.zsh"
}

case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  *)
    echo "[$MODULE_NAME] unknown action: $ACTION" >&2
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
