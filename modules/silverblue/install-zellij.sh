#!/bin/bash
# Glimt module: zellij
# Actions: all | deps | install | config | clean

set -uo pipefail

MODULE_NAME="zellij"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
BREW_PREFIX="$HOME_DIR/.linuxbrew"
ZELLIJ_CONFIG_DIR="$HOME_DIR/.config/zellij"
ZELLIJ_CONFIG_FILE="$ZELLIJ_CONFIG_DIR/config.kdl"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/zellij.zsh"
ZSH_TARGET_CONFIG="$ZSH_CONFIG_DIR/zellij.zsh"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_user() {
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

deps() {
  log "📦 Checking for brew..."
  if check_brew; then
    log "✅ brew is available"
  else
    exit 1
  fi
}

install() {
  require_user

  if ! check_brew; then
    exit 1
  fi

  log "🔌 Installing zellij via Homebrew..."

  if brew list zellij &>/dev/null; then
    log "🔄 Zellij already installed, upgrading..."
    brew upgrade zellij
    log "✅ Zellij upgraded"
  else
    log "⬇️  Installing zellij..."
    brew install zellij
    log "✅ Zellij installed"
  fi

  if ! command -v zellij &>/dev/null 2>&1; then
    log "❌ zellij command not found after installation"
    exit 1
  fi

  log "✅ Zellij is ready: $(command -v zellij)"
}

config() {
  require_user

  log "🔧 Configuring Zellij..."

  if ! command -v zellij &>/dev/null 2>&1; then
    log "❌ zellij command not found. Run 'install' first."
    exit 1
  fi

  log "⚙️  Setting up Zellij theme..."
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

copy_on_select true                 // selecting text copies immediately
copy_clipboard "system"             // use system clipboard (not PRIMARY)
copy_command "wl-copy"              // how to copy on Wayland
paste_command "wl-paste --no-newline"
mouse_mode true                     // keep mouse features in panes
EOF

  log "✅ Theme written to $ZELLIJ_CONFIG_FILE"

  log "📁 Installing Zsh config..."
  mkdir -p "$ZSH_CONFIG_DIR"
  if [[ -f "$TEMPLATE_FILE" ]]; then
    cp "$TEMPLATE_FILE" "$ZSH_TARGET_CONFIG"
    log "✅ Copied: $TEMPLATE_FILE → $ZSH_TARGET_CONFIG"
  else
    log "⚠️  Template $TEMPLATE_FILE not found; skipping Zsh config copy"
  fi

  log "✅ Zellij configuration complete"
}

clean() {
  require_user

  log "🧹 Removing Zellij..."

  # Remove zsh config
  if [[ -f "$ZSH_TARGET_CONFIG" ]]; then
    rm -f "$ZSH_TARGET_CONFIG"
    log "✅ Removed Zsh config: $ZSH_TARGET_CONFIG"
  fi

  # Remove Zellij config
  if [[ -d "$ZELLIJ_CONFIG_DIR" ]]; then
    rm -rf "$ZELLIJ_CONFIG_DIR"
    log "✅ Removed config: $ZELLIJ_CONFIG_DIR"
  fi

  # Uninstall zellij via Homebrew if available
  if check_brew && brew list zellij &>/dev/null; then
    log "🔄 Uninstalling zellij via Homebrew..."
    brew uninstall zellij
    log "✅ Zellij uninstalled"
  else
    log "ℹ️  Zellij not installed via Homebrew (or brew not available)"
  fi

  log "✅ Clean complete"
}

case "$ACTION" in
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
all)
  deps
  install
  config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac
