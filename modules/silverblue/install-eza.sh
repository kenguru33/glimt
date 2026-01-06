#!/usr/bin/env bash
# Glimt module: eza (modern ls replacement)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ eza module failed." >&2' ERR

MODULE_NAME="eza"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
BREW_PREFIX="$HOME_DIR/.linuxbrew"

ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_FILE="$ZSH_CONFIG_DIR/eza.zsh"

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
  if command -v brew &>/dev/null; then
    return 0
  fi

  # Try to source homebrew shellenv if brew is in standard location
  if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
    eval "$("$BREW_PREFIX/bin/brew" shellenv)"
    if command -v brew &>/dev/null; then
      return 0
    fi
  fi

  log "❌ brew command not found"
  log "ℹ Please ensure Homebrew is installed and available in PATH"
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

  log "🔌 Installing eza via Homebrew..."

  if brew list eza &>/dev/null; then
    log "🔄 eza already installed, upgrading..."
    brew upgrade eza
    log "✅ eza upgraded"
  else
    log "⬇️  Installing eza..."
    brew install eza
    log "✅ eza installed"
  fi

  if ! command -v eza &>/dev/null 2>&1; then
    log "❌ eza command not found after installation"
    exit 1
  fi

  log "✅ eza is ready: $(command -v eza)"
}

config() {
  require_user

  log "🔧 Configuring eza (aliases)..."

  if ! command -v eza &>/dev/null 2>&1; then
    log "❌ eza command not found. Run 'install' first."
    exit 1
  fi

  # Create zsh config if zsh config directory exists
  if [[ -d "$ZSH_CONFIG_DIR" ]]; then
    mkdir -p "$ZSH_CONFIG_DIR"
    cat >"$ZSH_FILE" <<'EOF'
# eza - modern ls replacement
if command -v eza &>/dev/null; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -l --group-directories-first --icons=auto'
  alias la='eza -la --group-directories-first --icons=auto'
  alias lt='eza -T --group-directories-first --icons=auto'
fi
EOF
    log "✅ Zsh config installed at $ZSH_FILE"
  else
    log "ℹ️ Zsh config directory $ZSH_CONFIG_DIR does not exist; skipping shell config"
  fi

  log "✅ eza configuration complete"
}

clean() {
  require_user

  log "🧹 Removing eza config..."

  # Remove zsh config
  if [[ -f "$ZSH_FILE" ]]; then
    rm -f "$ZSH_FILE"
    log "✅ Removed zsh config"
  fi

  # Uninstall eza via Homebrew if available
  if check_brew && brew list eza &>/dev/null; then
    log "🔄 Uninstalling eza via Homebrew..."
    brew uninstall eza
    log "✅ eza uninstalled"
  else
    log "ℹ️ eza not installed via Homebrew (or brew not available)"
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

