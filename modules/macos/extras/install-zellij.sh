#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="zellij"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ZELLIJ_CONFIG_DIR="$HOME_DIR/.config/zellij"
ZELLIJ_CONFIG_FILE="$ZELLIJ_CONFIG_DIR/config.kdl"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

macos_guard() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
}

deps() { log "No additional dependencies."; }

install() {
  log "Installing Zellij via Homebrew..."
  brew install zellij
  verify_binary zellij --version
}

config() {
  log "Configuring Zellij theme..."
  mkdir -p "$ZELLIJ_CONFIG_DIR"

  cat > "$ZELLIJ_CONFIG_FILE" <<'EOF'
theme "catppuccin-mocha"

themes {
  catppuccin-mocha {
    fg "#cdd6f4"
    bg "#1e1e2e"
    black "#45475a"
    red "#f38ba8"
    green "#a6e3a1"
    yellow "#f9e2af"
    blue "#89b4fa"
    magenta "#f5c2e7"
    cyan "#94e2d5"
    white "#bac2de"
    orange "#fab387"
  }
}

default_layout "compact"
default_mode "normal"

copy_on_select true
copy_clipboard "system"
copy_command "pbcopy"
mouse_mode true
EOF

  log "✅ Theme written to $ZELLIJ_CONFIG_FILE"

  log "Deploying zellij.zsh config..."
  mkdir -p "$ZSH_CONFIG_DIR"
  deploy_config "$SCRIPT_DIR/../config/zellij.zsh" "$ZSH_CONFIG_DIR/zellij.zsh"
}

clean() {
  brew uninstall zellij 2>/dev/null || true
  rm -rf "$ZELLIJ_CONFIG_DIR"
  rm -f "$ZSH_CONFIG_DIR/zellij.zsh"
}

macos_guard

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
