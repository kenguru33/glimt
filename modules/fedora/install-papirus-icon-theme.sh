#!/usr/bin/env bash
# Glimt module: papirus-icon-theme
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="papirus-icon-theme"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

ICONS_DIR="$HOME_DIR/.local/share/icons"
PAPIRUS_DIR="$ICONS_DIR/Papirus"
# Every theme directory the upstream installer creates
PAPIRUS_VARIANTS=(Papirus Papirus-Dark Papirus-Light ePapirus ePapirus-Dark)
# Upstream installer — always installs the latest release (not pinned)
INSTALLER_URL="https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh"

require_user() {
  if [[ "$EUID" -eq 0 ]]; then
    echo "❌ Do not run this module as root." >&2
    exit 1
  fi
}

deps() {
  log "📦 Installing dependencies..."
  sudo dnf install -y curl tar
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

  command -v curl &>/dev/null || die "curl not found — run 'deps' first"
  local installer
  installer="$(curl -fsSL "$INSTALLER_URL")" || die "Could not download $INSTALLER_URL"
  DESTDIR="$ICONS_DIR" sh -c "$installer"

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

  local variant removed=0
  for variant in "${PAPIRUS_VARIANTS[@]}"; do
    if [[ -d "$ICONS_DIR/$variant" ]]; then
      rm -rf "${ICONS_DIR:?}/$variant"
      log "🔄 Removed $variant"
      removed=1
    fi
  done
  (( removed )) || log "ℹ️  papirus-icon-theme not installed"

  # config set Papirus as the icon theme — reset it, unless the user has
  # switched to another theme since
  if command -v gsettings &>/dev/null; then
    local current
    current="$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null || true)"
    if [[ "$current" == "'Papirus"* || "$current" == "'ePapirus"* ]]; then
      gsettings reset org.gnome.desktop.interface icon-theme || true
      log "🔄 Reset icon theme to the GNOME default"
    fi
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
  die "Unknown action: $ACTION (use: all | deps | install | config | clean)"
  ;;
esac
