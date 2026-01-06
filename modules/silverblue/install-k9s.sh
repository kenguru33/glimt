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

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_user() {
  # Silverblue: run as regular user, not root
  if [[ "$EUID" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    echo "❌ Do not run this module as root directly." >&2
    exit 1
  fi
}

check_brew() {
  # Check if brew command is available in PATH
  if command -v brew &>/dev/null 2>&1; then
    return 0
  fi
  
  local BREW_PREFIX="$HOME_DIR/.linuxbrew"
  
  # Try multiple possible Homebrew locations
  local possible_paths=(
    "$BREW_PREFIX/bin/brew"
    "$HOME_DIR/.linuxbrew/bin/brew"
    "$HOME/.linuxbrew/bin/brew"
    "/home/linuxbrew/.linuxbrew/bin/brew"
  )
  
  local brew_path=""
  for path in "${possible_paths[@]}"; do
    if [[ -x "$path" ]]; then
      brew_path="$path"
      BREW_PREFIX="$(dirname "$(dirname "$path")")"
      break
    fi
  done
  
  # Check if brew exists and is executable
  if [[ -z "$brew_path" ]]; then
    log "❌ brew not found in any standard location"
    log "ℹ Checked paths:"
    for path in "${possible_paths[@]}"; do
      log "   - $path"
    done
    log "ℹ Please ensure Homebrew is installed via the prereq module first"
    log "ℹ Run: modules/silverblue/packages/install-silverblue-prereq.sh install"
    return 1
  fi
  
  log "🔍 Found brew at: $brew_path"
  
  # Source homebrew shellenv
  local shellenv_output
  shellenv_output=$("$brew_path" shellenv 2>&1) || {
    log "❌ Failed to get homebrew shellenv: $shellenv_output"
    return 1
  }
  
  # Evaluate the shellenv output
  eval "$shellenv_output" 2>/dev/null || true
  
  # Explicitly export PATH and Homebrew variables to ensure they're available
  export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH"
  export HOMEBREW_PREFIX="$BREW_PREFIX"
  export HOMEBREW_CELLAR="$BREW_PREFIX/Cellar"
  export HOMEBREW_REPOSITORY="$BREW_PREFIX/Homebrew"
  
  # Verify brew is now available
  if command -v brew &>/dev/null 2>&1; then
    log "✅ brew is now available: $(command -v brew)"
    return 0
  fi
  
  log "❌ brew command still not found after sourcing shellenv"
  log "ℹ Homebrew may be installed but not properly configured"
  log "ℹ Try running: eval \"\$($brew_path shellenv)\""
  return 1
}

install_dependencies() {
  require_user
  log "📦 Ensuring Homebrew (Linuxbrew) is available for installing K9s..."
  if check_brew; then
    log "✅ Homebrew detected."
  else
    log "⚠️  Homebrew not available"
    return 1
  fi
}

install_k9s() {
  require_user
  
  if ! check_brew; then
    log "❌ Homebrew not available. Cannot install k9s."
    exit 1
  fi

  log "🔧 Installing K9s via Homebrew..."

  if brew list k9s &>/dev/null; then
    log "🔄 k9s already installed, upgrading..."
    brew upgrade k9s
    log "✅ k9s upgraded"
  else
    log "⬇️  Installing k9s..."
    brew install k9s
    log "✅ k9s installed"
  fi

  # Make sure k9s is available in PATH
  if ! command -v k9s &>/dev/null 2>&1; then
    log "⚠️  k9s command not found after installation"
    log "ℹ️  k9s may be installed but not in PATH. Try sourcing Homebrew shellenv."
  else
    log "✅ k9s is ready: $(command -v k9s)"
  fi
}

config_k9s() {
  require_user
  log "🧠 Installing K9s config and theme..."

  # Source Homebrew environment to make k9s available
  if ! check_brew; then
    log "⚠️  Homebrew not available"
  fi

  # Check if k9s is available (might be in Homebrew's bin directory)
  if ! command -v k9s &>/dev/null 2>&1; then
    # Try to find k9s in Homebrew directories
    local k9s_path=""
    local possible_k9s_paths=(
      "$HOME_DIR/.linuxbrew/bin/k9s"
      "$HOME/.linuxbrew/bin/k9s"
      "/home/linuxbrew/.linuxbrew/bin/k9s"
    )
    
    for path in "${possible_k9s_paths[@]}"; do
      if [[ -x "$path" ]]; then
        k9s_path="$path"
        # Add to PATH temporarily
        export PATH="$(dirname "$path"):$PATH"
        break
      fi
    done
    
    if [[ -z "$k9s_path" ]] || ! command -v k9s &>/dev/null 2>&1; then
      log "⚠️  K9s binary not found in PATH. Run 'install' first (via Homebrew)."
      exit 1
    fi
  fi

  mkdir -p "$TARGET_CONFIG_DIR"
  if [[ -f "$CONFIG_TEMPLATE_DIR/k9s.zsh" ]]; then
    cp "$CONFIG_TEMPLATE_DIR/k9s.zsh" "$TARGET_CONFIG_FILE"
    log "✅ Installed Zsh completion config: $TARGET_CONFIG_FILE"
  fi

  mkdir -p "$HOME_DIR/.local/share/bash-completion/completions"
  k9s completion bash > "$HOME_DIR/.local/share/bash-completion/completions/k9s" || true

  mkdir -p "$HOME_DIR/.config/fish/completions"
  k9s completion fish > "$HOME_DIR/.config/fish/completions/k9s.fish" || true

  local SKIN_DIR="$HOME_DIR/.config/k9s/skins"
  mkdir -p "$SKIN_DIR"
  curl -fsSL https://raw.githubusercontent.com/catppuccin/k9s/main/dist/catppuccin-mocha.yaml \
    -o "$SKIN_DIR/catppuccin-mocha.yaml"
  log "✅ Theme saved to $SKIN_DIR/catppuccin-mocha.yaml"

  local CONFIG_FILE="$HOME_DIR/.config/k9s/config.yaml"
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat <<EOF > "$CONFIG_FILE"
k9s:
  ui:
    skin: catppuccin-mocha
EOF

  log "✅ config.yaml written with Catppuccin Mocha"
}

clean_k9s() {
  require_user
  log "🧹 Removing K9s and related files..."

  rm -f "$HOME_DIR/.local/share/bash-completion/completions/k9s"
  rm -f "$HOME_DIR/.config/fish/completions/k9s.fish"
  rm -rf "$HOME_DIR/.config/k9s"
  rm -f "$TARGET_CONFIG_FILE"

  # Uninstall k9s via Homebrew if available
  if check_brew && brew list k9s &>/dev/null; then
    log "🔄 Uninstalling k9s via Homebrew..."
    brew uninstall k9s
    log "✅ k9s uninstalled"
  else
    log "ℹ️  k9s not installed via Homebrew (or brew not available)"
  fi

  log "✅ All K9s files removed."
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

