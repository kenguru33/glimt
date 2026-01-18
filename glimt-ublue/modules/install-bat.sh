#!/usr/bin/env bash
# Glimt module: bat (cat alternative)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ Bat module failed." >&2' ERR

MODULE_NAME="bat"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
BREW_PREFIX="$HOME_DIR/.linuxbrew"

BAT_THEME_NAME="Catppuccin Mocha"
BAT_BIN="bat"
THEME_VARIANTS=(Latte Frappe Macchiato Mocha)
THEME_REPO_BASE="https://github.com/catppuccin/bat/raw/main/themes"

ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_FILE="$ZSH_CONFIG_DIR/bat.zsh"

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

  log "🔌 Installing bat via Homebrew..."

  if brew list bat &>/dev/null; then
    log "🔄 Bat already installed, upgrading..."
    brew upgrade bat
    log "✅ Bat upgraded"
  else
    log "⬇️  Installing bat..."
    brew install bat
    log "✅ Bat installed"
  fi

  if ! command -v bat &>/dev/null 2>&1; then
    log "❌ bat command not found after installation"
    exit 1
  fi

  log "✅ Bat is ready: $(command -v bat)"
}

config() {
  require_user

  log "🔧 Configuring bat..."

  if ! command -v bat &>/dev/null 2>&1; then
    log "❌ bat command not found. Run 'install' first."
    exit 1
  fi

  # Get bat config directory
  BAT_CONFIG_DIR="$(bat --config-dir)"
  BAT_THEME_DIR="$BAT_CONFIG_DIR/themes"
  BAT_CONFIG_FILE="$BAT_CONFIG_DIR/config"

  mkdir -p "$BAT_THEME_DIR"

  log "🎨 Installing Catppuccin themes..."

  # Use curl if available (more reliable), otherwise fall back to wget
  for variant in "${THEME_VARIANTS[@]}"; do
    local theme_file="$BAT_THEME_DIR/Catppuccin ${variant}.tmTheme"
    local theme_url="$THEME_REPO_BASE/Catppuccin%20${variant}.tmTheme"
    
    if command -v curl &>/dev/null 2>&1; then
      curl -fsSL -o "$theme_file" "$theme_url" || {
        log "⚠️  Failed to download Catppuccin ${variant} theme"
        continue
      }
    elif command -v wget &>/dev/null 2>&1; then
      wget --quiet --output-document="$theme_file" "$theme_url" || {
        log "⚠️  Failed to download Catppuccin ${variant} theme"
        continue
      }
    else
      log "❌ Neither curl nor wget found. Cannot download themes."
      exit 1
    fi
  done

  log "🧹 Rebuilding theme cache..."
  bat cache --build || {
    log "⚠️  Failed to rebuild theme cache (themes may still work)"
  }

  log "⚙️ Setting default theme: $BAT_THEME_NAME"
  echo "--theme=\"$BAT_THEME_NAME\"" > "$BAT_CONFIG_FILE"
  
  log "✅ Catppuccin themes installed successfully"

  # Create zsh config if zsh config directory exists
  if [[ -d "$ZSH_CONFIG_DIR" ]]; then
    mkdir -p "$ZSH_CONFIG_DIR"
    cat >"$ZSH_FILE" <<'EOF'
# bat - cat alternative with syntax highlighting
if command -v bat &>/dev/null; then
  # Use bat instead of cat
  alias cat='bat --paging=never'
  alias catp='bat'  # bat with paging enabled
fi
EOF
    log "✅ Zsh config installed at $ZSH_FILE"
  fi

  log "✅ Bat configuration complete"
}

clean() {
  require_user

  log "🧹 Removing bat themes and config..."

  # Remove bat config and themes
  if command -v bat &>/dev/null 2>&1; then
    BAT_CONFIG_DIR="$(bat --config-dir 2>/dev/null || echo "$HOME_DIR/.config/bat")"
  else
    BAT_CONFIG_DIR="$HOME_DIR/.config/bat"
  fi
  BAT_THEME_DIR="$BAT_CONFIG_DIR/themes"
  BAT_CONFIG_FILE="$BAT_CONFIG_DIR/config"
  BAT_CACHE_DIR="$HOME_DIR/.cache/bat"

  rm -rf "$BAT_THEME_DIR" "$BAT_CONFIG_FILE" "$BAT_CACHE_DIR"
  log "✅ Bat config and themes removed"

  # Remove zsh config
  if [[ -f "$ZSH_FILE" ]]; then
    rm -f "$ZSH_FILE"
    log "✅ Removed zsh config"
  fi

  # Uninstall bat via Homebrew if available
  if check_brew && brew list bat &>/dev/null; then
    log "🔄 Uninstalling bat via Homebrew..."
    brew uninstall bat
    log "✅ Bat uninstalled"
  else
    log "ℹ️  Bat not installed via Homebrew (or brew not available)"
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
