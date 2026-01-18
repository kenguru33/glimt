#!/bin/bash
# Glimt module: papirus-icon-theme
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ papirus-icon-theme module failed." >&2' ERR

MODULE_NAME="papirus-icon-theme"
ACTION="${1:-all}"

HOME_DIR="$HOME"
ICONS_DIR="$HOME_DIR/.local/share/icons"
PAPIRUS_DIR="$ICONS_DIR/Papirus"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_user() {
  if [[ "$EUID" -eq 0 ]]; then
    echo "❌ Do not run this module as root." >&2
    exit 1
  fi
}

deps() {
  log "📦 Checking dependencies..."
  
  if ! command -v wget &>/dev/null 2>&1 && ! command -v curl &>/dev/null 2>&1; then
    log "❌ Neither wget nor curl found. Please install one of them first."
    exit 1
  fi
  
  log "✅ Dependencies available"
}

install() {
  require_user

  log "🔌 Installing papirus-icon-theme from git..."

  if [[ -d "$PAPIRUS_DIR" ]]; then
    log "✅ papirus-icon-theme already installed at $PAPIRUS_DIR"
    log "ℹ️  To update, run 'clean' first, then 'install' again"
    return
  fi

  log "⬇️  Downloading and installing papirus-icon-theme..."
  mkdir -p "$ICONS_DIR"

  if command -v wget &>/dev/null 2>&1; then
    wget -qO- https://git.io/papirus-icon-theme-install | DESTDIR="$ICONS_DIR" sh
  elif command -v curl &>/dev/null 2>&1; then
    curl -fsSL https://git.io/papirus-icon-theme-install | DESTDIR="$ICONS_DIR" sh
  else
    log "❌ Neither wget nor curl available"
    exit 1
  fi

  if [[ -d "$PAPIRUS_DIR" ]]; then
    log "✅ papirus-icon-theme installed successfully to $PAPIRUS_DIR"
  else
    log "❌ papirus-icon-theme installation failed"
    exit 1
  fi
}

config() {
  require_user

  log "🔧 Configuring papirus-icon-theme..."

  if [[ ! -d "$PAPIRUS_DIR" ]]; then
    log "❌ papirus-icon-theme not found. Run 'install' first."
    exit 1
  fi

  log "⚙️  Setting Papirus icon theme as default..."
  if command -v gsettings &>/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface icon-theme "Papirus"
    log "✅ Papirus is now the default icon theme"
  else
    log "⚠️  gsettings not available; cannot set theme automatically"
    log "ℹ️  You can set it manually in GNOME Settings > Appearance"
  fi

  log "✅ papirus-icon-theme configuration complete"
}

clean() {
  require_user

  log "🧹 Removing papirus-icon-theme..."

  if [[ -d "$PAPIRUS_DIR" ]]; then
    log "🔄 Removing papirus-icon-theme from $PAPIRUS_DIR..."
    rm -rf "$PAPIRUS_DIR"
    
    # Also remove other Papirus variants if they exist
    for variant in Papirus-Dark Papirus-Light; do
      if [[ -d "$ICONS_DIR/$variant" ]]; then
        rm -rf "$ICONS_DIR/$variant"
        log "🔄 Removed $variant"
      fi
    done
    
    log "✅ papirus-icon-theme removed"
  else
    log "ℹ️  papirus-icon-theme not installed"
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
