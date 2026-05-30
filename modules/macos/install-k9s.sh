#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="k9s"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
K9S_CONFIG_DIR="$HOME_DIR/.config/k9s"
SKIN_DIR="$K9S_CONFIG_DIR/skins"

deps() { log "No additional dependencies."; }

install() {
  if brew list k9s &>/dev/null; then
    log "k9s already installed."
  else
    brew install k9s
  fi
  verify_binary k9s version
}

config() {
  mkdir -p "$SKIN_DIR"

  log "Downloading Catppuccin Mocha skin..."
  curl -fsSL https://raw.githubusercontent.com/catppuccin/k9s/main/dist/catppuccin-mocha.yaml \
    -o "$SKIN_DIR/catppuccin-mocha.yaml"

  log "Writing config.yaml..."
  cat >"$K9S_CONFIG_DIR/config.yaml" <<'EOF'
k9s:
  ui:
    skin: catppuccin-mocha
EOF

  deploy_config "$SCRIPT_DIR/config/k9s.zsh" "$ZSH_CONFIG_DIR/k9s.zsh"
}

clean() {
  brew uninstall k9s 2>/dev/null || true
  rm -rf "$K9S_CONFIG_DIR"
  rm -f "$ZSH_CONFIG_DIR/k9s.zsh"
}

case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
