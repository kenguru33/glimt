#!/usr/bin/env bash
# Glimt module: helm (Kubernetes package manager)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ helm module failed." >&2' ERR

MODULE_NAME="helm"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
BREW_PREFIX="$HOME_DIR/.linuxbrew"

ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_COMP_DIR="$HOME_DIR/.zsh/completions"
ZSH_FILE="$ZSH_CONFIG_DIR/helm.zsh"

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

  log "🔌 Installing helm via Homebrew..."

  if brew list helm &>/dev/null; then
    log "🔄 helm already installed, upgrading..."
    brew upgrade helm
    log "✅ helm upgraded"
  else
    log "⬇️  Installing helm..."
    brew install helm
    log "✅ helm installed"
  fi

  if ! command -v helm &>/dev/null 2>&1; then
    log "❌ helm command not found after installation"
    exit 1
  fi

  log "✅ helm is ready: $(command -v helm)"
}

config() {
  require_user

  log "🔧 Configuring helm (completion and aliases)..."

  if ! command -v helm &>/dev/null 2>&1; then
    log "❌ helm command not found. Run 'install' first."
    exit 1
  fi

  # Install zsh completion to ~/.zsh/completions if directory exists
  if [[ -d "$HOME_DIR/.zsh" ]]; then
    mkdir -p "$ZSH_COMP_DIR"
    if helm completion zsh >"$ZSH_COMP_DIR/_helm"; then
      log "✅ Zsh completion installed at $ZSH_COMP_DIR/_helm"
    else
      log "⚠️  Failed to generate helm zsh completion"
    fi
  fi

  # Create zsh config if zsh config directory exists
  if [[ -d "$ZSH_CONFIG_DIR" ]]; then
    mkdir -p "$ZSH_CONFIG_DIR"
    cat >"$ZSH_FILE" <<'EOF'
# helm - Kubernetes package manager
if command -v helm &>/dev/null; then
  alias h='helm'
fi
EOF
    log "✅ Zsh config installed at $ZSH_FILE"
  else
    log "ℹ️ Zsh config directory $ZSH_CONFIG_DIR does not exist; skipping shell config"
  fi

  log "✅ helm configuration complete"
}

clean() {
  require_user

  log "🧹 Removing helm config..."

  # Remove zsh completion
  if [[ -f "$ZSH_COMP_DIR/_helm" ]]; then
    rm -f "$ZSH_COMP_DIR/_helm"
    log "✅ Removed helm zsh completion"
  fi

  # Remove zsh config
  if [[ -f "$ZSH_FILE" ]]; then
    rm -f "$ZSH_FILE"
    log "✅ Removed zsh config"
  fi

  # Uninstall helm via Homebrew if available
  if check_brew && brew list helm &>/dev/null; then
    log "🔄 Uninstalling helm via Homebrew..."
    brew uninstall helm
    log "✅ helm uninstalled"
  else
    log "ℹ️ helm not installed via Homebrew (or brew not available)"
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

