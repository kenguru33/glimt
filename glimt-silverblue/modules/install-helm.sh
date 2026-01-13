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

