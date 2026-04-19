#!/usr/bin/env bash
# Glimt module: gnome-caffeine
# Fedora Workstation
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ gnome-caffeine failed at line $LINENO" >&2' ERR

MODULE_NAME="gnome-caffeine"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

PKG="gnome-shell-extension-caffeine"
EXT_UUID="caffeine@patapon.info"

require_gnome() {
  command -v gnome-shell >/dev/null || die "GNOME not detected"
  [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || die "Run from GNOME session (not sudo / tty / ssh)"
}

deps() {
  log "Installing $PKG…"
  sudo dnf install -y "$PKG"
}

install() {
  log "Caffeine extension installed via DNF."
}

config() {
  require_gnome
  log "Enabling $EXT_UUID"
  gnome-extensions enable "$EXT_UUID" || warn "Could not enable $EXT_UUID — you may need to log out and back in first"
  log "Configuration complete"
}

clean() {
  gnome-extensions disable "$EXT_UUID" 2>/dev/null || true
  gnome-extensions uninstall "$EXT_UUID" 2>/dev/null || true
  sudo dnf remove -y "$PKG" || true
  log "Removed $PKG"
}

case "$ACTION" in
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  all)
    deps
    install
    config
    ;;
  *)
    die "Unknown action: $ACTION (use: all | deps | install | config | clean)"
    ;;
esac
