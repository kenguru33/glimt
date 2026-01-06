#!/usr/bin/env bash
# Glimt module: azure-cli
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ azure-cli module failed." >&2' ERR

MODULE_NAME="azure-cli"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
BREW_PREFIX="$HOME_DIR/.linuxbrew"

ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_COMP_DIR="$HOME_DIR/.zsh/completions"
ZSH_FILE="$ZSH_CONFIG_DIR/azure-cli.zsh"

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

  log "🔌 Installing azure-cli via Homebrew..."

  if brew list azure-cli &>/dev/null; then
    log "🔄 azure-cli already installed, upgrading..."
    brew upgrade azure-cli
    log "✅ azure-cli upgraded"
  else
    log "⬇️  Installing azure-cli..."
    brew install azure-cli
    log "✅ azure-cli installed"
  fi

  if ! command -v az &>/dev/null 2>&1; then
    log "❌ az command not found after installation"
    exit 1
  fi

  log "✅ azure-cli is ready: $(command -v az)"
}

config() {
  require_user

  log "🔧 Configuring azure-cli (helpers)..."

  if ! command -v az &>/dev/null 2>&1; then
    log "❌ az command not found. Run 'install' first."
    exit 1
  fi

  # Create zsh config if zsh config directory exists (same pattern as Fedora/Debian modules)
  if [[ -d "$ZSH_CONFIG_DIR" ]]; then
    mkdir -p "$ZSH_CONFIG_DIR"
    cat >"$ZSH_FILE" <<'EOF'
# azure-cli - Azure command-line interface
if command -v az &>/dev/null; then
  alias azlogin='az login --use-device-code'
fi
EOF
    log "✅ Zsh config installed at $ZSH_FILE"
  else
    log "ℹ️ Zsh config directory $ZSH_CONFIG_DIR does not exist; skipping shell config"
  fi

  log "✅ azure-cli configuration complete"
}

clean() {
  require_user

  log "🧹 Removing azure-cli config..."

  # Remove zsh config
  if [[ -f "$ZSH_FILE" ]]; then
    rm -f "$ZSH_FILE"
    log "✅ Removed zsh config"
  fi

  # Uninstall azure-cli via Homebrew if available
  if check_brew && brew list azure-cli &>/dev/null; then
    log "🔄 Uninstalling azure-cli via Homebrew..."
    brew uninstall azure-cli
    log "✅ azure-cli uninstalled"
  else
    log "ℹ️ azure-cli not installed via Homebrew (or brew not available)"
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

