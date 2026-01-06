#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ An error occurred in K9s installer. Exiting." >&2' ERR

MODULE_NAME="k9s"
K9S_VERSION="v0.32.4"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
CONFIG_TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config"
TARGET_CONFIG_DIR="$HOME_DIR/.zsh/config"
TARGET_CONFIG_FILE="$TARGET_CONFIG_DIR/k9s.zsh"

require_user() {
  # Silverblue: run as regular user, not root
  if [[ "$EUID" -eq 0 ]]; then
    echo "❌ Do not run this module as root. Run it as your normal user (no sudo)."
    exit 1
  fi
}

install_dependencies() {
  require_user
  echo "📦 Ensuring Homebrew (Linuxbrew) is available for installing K9s..."
  if ! command -v brew >/dev/null 2>&1 && \
     [[ ! -x "$HOME_DIR/.linuxbrew/bin/brew" ]] && \
     [[ ! -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    echo "⚠️  Homebrew not found in PATH, $HOME_DIR/.linuxbrew, or /home/linuxbrew/.linuxbrew."
    echo "   Run 'modules/silverblue/install-homebrew.sh all' or ensure brew is available."
  else
    echo "✅ Homebrew detected."
  fi
}

install_k9s() {
  require_user
  echo "🔧 Installing K9s via Homebrew..."

  # Resolve brew from several common locations
  local BREW_BIN_RESOLVED=""

  if command -v brew >/dev/null 2>&1; then
    BREW_BIN_RESOLVED="$(command -v brew)"
  elif [[ -x "$HOME_DIR/.linuxbrew/bin/brew" ]]; then
    BREW_BIN_RESOLVED="$HOME_DIR/.linuxbrew/bin/brew"
  elif [[ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    BREW_BIN_RESOLVED="/home/linuxbrew/.linuxbrew/bin/brew"
  fi

  if [[ -z "$BREW_BIN_RESOLVED" ]]; then
    echo "❌ brew not found in PATH, $HOME_DIR/.linuxbrew/bin/brew, or /home/linuxbrew/.linuxbrew/bin/brew"
    echo "   Run 'modules/silverblue/install-homebrew.sh all' or adjust BREW_BIN_RESOLVED logic."
    exit 1
  fi

  "$BREW_BIN_RESOLVED" install k9s

  echo "✅ K9s installed via Homebrew"
}

config_k9s() {
  require_user
  echo "🧠 Installing K9s config and theme..."

  if ! command -v k9s >/dev/null 2>&1; then
    echo "⚠️  K9s binary not found in PATH. Run 'install' first (via Homebrew)."
    exit 1
  fi

  mkdir -p "$TARGET_CONFIG_DIR"
  if [[ -f "$CONFIG_TEMPLATE_DIR/k9s.zsh" ]]; then
    cp "$CONFIG_TEMPLATE_DIR/k9s.zsh" "$TARGET_CONFIG_FILE"
    echo "✅ Installed Zsh completion config: $TARGET_CONFIG_FILE"
  fi

  mkdir -p "$HOME_DIR/.local/share/bash-completion/completions"
  k9s completion bash > "$HOME_DIR/.local/share/bash-completion/completions/k9s" || true

  mkdir -p "$HOME_DIR/.config/fish/completions"
  k9s completion fish > "$HOME_DIR/.config/fish/completions/k9s.fish" || true

  local SKIN_DIR="$HOME_DIR/.config/k9s/skins"
  mkdir -p "$SKIN_DIR"
  curl -fsSL https://raw.githubusercontent.com/catppuccin/k9s/main/dist/catppuccin-mocha.yaml \
    -o "$SKIN_DIR/catppuccin-mocha.yaml"
  echo "✅ Theme saved to $SKIN_DIR/catppuccin-mocha.yaml"

  local CONFIG_FILE="$HOME_DIR/.config/k9s/config.yaml"
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat <<EOF > "$CONFIG_FILE"
k9s:
  ui:
    skin: catppuccin-mocha
EOF

  echo "✅ config.yaml written with Catppuccin Mocha"
}

clean_k9s() {
  require_user
  echo "🧹 Removing K9s and related files..."

  rm -f "$HOME_DIR/.local/share/bash-completion/completions/k9s"
  rm -f "$HOME_DIR/.config/fish/completions/k9s.fish"
  rm -rf "$HOME_DIR/.config/k9s"
  rm -f "$TARGET_CONFIG_FILE"

  echo "✅ All K9s files removed."
}

case "$ACTION" in
  deps)    install_dependencies ;;
  install) install_k9s ;;
  config)  config_k9s ;;
  clean)   clean_k9s ;;
  all)     install_dependencies; install_k9s; config_k9s ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

