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

# --------------------------------------------------
# Homebrew detection + shellenv
# --------------------------------------------------
check_brew() {
  if command -v brew &>/dev/null; then
    return 0
  fi

  local candidates=(
    "$BREW_PREFIX/bin/brew"
    "/home/linuxbrew/.linuxbrew/bin/brew"
  )

  for path in "${candidates[@]}"; do
    if [[ -x "$path" ]]; then
      eval "$("$path" shellenv)" >/dev/null 2>&1 || true
      export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH"
      command -v brew &>/dev/null && return 0
    fi
  done

  log "❌ brew not found"
  return 1
}

# --------------------------------------------------
# SAFE Homebrew install (warnings ≠ failure)
# --------------------------------------------------
brew_install_safe() {
  local pkg="$1"

  log "🍺 Installing $pkg via Homebrew..."

  set +e
  brew install "$pkg"
  local rc=$?
  set -e

  if brew list --formula "$pkg" &>/dev/null; then
    if [[ $rc -ne 0 ]]; then
      log "⚠️  $pkg installed with warnings (acceptable)"
    else
      log "✅ $pkg installed"
    fi
    return 0
  fi

  log "❌ $pkg not installed"
  return 1
}

deps() {
  log "📦 Checking for brew..."
  check_brew || exit 1
  log "✅ brew is available"
}

install() {
  require_user
  check_brew || exit 1

  log "🔌 Installing btop via Homebrew..."

  export HOMEBREW_NO_INSTALL_CLEANUP=1
  export HOMEBREW_NO_ENV_HINTS=1

  if brew list --formula btop &>/dev/null; then
    log "🔄 btop already installed, attempting upgrade..."
    set +e
    brew upgrade btop
    set -e
  else
    brew_install_safe btop
  fi

  command -v btop &>/dev/null || {
    log "❌ btop command not found after install"
    exit 1
  }

  log "✅ btop is ready: $(command -v btop)"
}

config() {
  require_user

  log "🎨 Applying Catppuccin Mocha theme to btop..."

  command -v btop &>/dev/null || {
    log "❌ btop not installed"
    exit 1
  }

  mkdir -p "$BTOP_THEME_DIR"

  local theme_file="$BTOP_THEME_DIR/catppuccin_mocha.theme"
  curl -fsSL "$CATPPUCCIN_THEME_URL" -o "$theme_file"

  mkdir -p "$BTOP_CONFIG_DIR"

  if [[ ! -f "$BTOP_CONFIG_FILE" ]]; then
    TERM=xterm-256color btop --write-config </dev/null >/dev/null 2>&1 || true
  fi

  if grep -q '^color_theme' "$BTOP_CONFIG_FILE" 2>/dev/null; then
    sed -i 's/^color_theme.*/color_theme = "catppuccin_mocha"/' "$BTOP_CONFIG_FILE"
  else
    echo 'color_theme = "catppuccin_mocha"' >>"$BTOP_CONFIG_FILE"
  fi

  log "✅ Theme applied"
}

clean() {
  require_user

  log "🧹 Cleaning btop config..."
  rm -f "$BTOP_THEME_DIR/catppuccin_mocha.theme" "$BTOP_CONFIG_FILE" 2>/dev/null || true

  if check_brew && brew list --formula btop &>/dev/null; then
    brew uninstall btop || true
    log "✅ btop uninstalled"
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
