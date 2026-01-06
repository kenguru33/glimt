#!/usr/bin/env bash
# Glimt module: btop (resource monitor)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ btop module failed." >&2' ERR

MODULE_NAME="btop"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
BREW_PREFIX="$HOME_DIR/.linuxbrew"

BTOP_CONFIG_DIR="$HOME_DIR/.config/btop"
BTOP_THEME_DIR="$BTOP_CONFIG_DIR/themes"
BTOP_CONFIG_FILE="$BTOP_CONFIG_DIR/btop.conf"
CATPPUCCIN_THEME_URL="https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_mocha.theme"

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

  log "🔌 Installing btop via Homebrew..."

  if brew list btop &>/dev/null; then
    log "🔄 btop already installed, upgrading..."
    brew upgrade btop
    log "✅ btop upgraded"
  else
    log "⬇️  Installing btop..."
    brew install btop
    log "✅ btop installed"
  fi

  if ! command -v btop &>/dev/null 2>&1; then
    log "❌ btop command not found after installation"
    exit 1
  fi

  log "✅ btop is ready: $(command -v btop)"
}

config() {
  require_user

  log "🎨 Applying Catppuccin Mocha theme to btop..."

  if ! command -v btop &>/dev/null 2>&1; then
    log "❌ btop command not found. Run 'install' first."
    exit 1
  fi

  mkdir -p "$BTOP_THEME_DIR"

  # Download theme using curl or wget
  local theme_file="$BTOP_THEME_DIR/catppuccin_mocha.theme"
  if command -v curl &>/dev/null 2>&1; then
    log "⬇️  Downloading Catppuccin Mocha theme with curl..."
    curl -fsSL -o "$theme_file" "$CATPPUCCIN_THEME_URL"
  elif command -v wget &>/dev/null 2>&1; then
    log "⬇️  Downloading Catppuccin Mocha theme with wget..."
    wget -qO "$theme_file" "$CATPPUCCIN_THEME_URL"
  else
    log "❌ Neither curl nor wget found. Cannot download theme."
    exit 1
  fi

  log "🛠 Ensuring btop config exists..."
  mkdir -p "$BTOP_CONFIG_DIR"

  if [[ ! -f "$BTOP_CONFIG_FILE" ]]; then
    log "🧪 Attempting to generate config using btop..."
    if TERM=xterm-256color btop --write-config </dev/null >/dev/null 2>&1; then
      log "✅ Generated btop config via btop --write-config"
    else
      log "⚠️ btop --write-config failed. Creating minimal config manually."
      echo 'color_theme = "catppuccin_mocha"' >"$BTOP_CONFIG_FILE"
    fi
  fi

  log "🎯 Setting color_theme to catppuccin_mocha..."
  if grep -q '^color_theme' "$BTOP_CONFIG_FILE" 2>/dev/null; then
    sed -i 's/^color_theme.*/color_theme = "catppuccin_mocha"/' "$BTOP_CONFIG_FILE"
  else
    echo 'color_theme = "catppuccin_mocha"' >>"$BTOP_CONFIG_FILE"
  fi

  log "✅ Theme set to catppuccin_mocha in $BTOP_CONFIG_FILE"
}

clean() {
  require_user

  log "🧹 Removing btop config and theme..."
  rm -f "$BTOP_THEME_DIR/catppuccin_mocha.theme" 2>/dev/null || true
  rm -f "$BTOP_CONFIG_FILE" 2>/dev/null || true
  log "✅ btop theme and config removed."

  # Uninstall btop via Homebrew if available
  if check_brew && brew list btop &>/dev/null; then
    log "🔄 Uninstalling btop via Homebrew..."
    brew uninstall btop
    log "✅ btop uninstalled"
  else
    log "ℹ️ btop not installed via Homebrew (or brew not available)"
  fi
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

