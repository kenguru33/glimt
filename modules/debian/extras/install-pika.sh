#!/usr/bin/env bash
# Glimt module: Install Pika Backup (Flatpak)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="pika-backup"
FLATPAK_ID="org.gnome.World.PikaBackup"
ACTION="${1:-all}"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

deps() {
  log "Ensuring Flatpak is available"
  command -v flatpak >/dev/null || die "Flatpak is not installed"
}

install() {
  log "Installing Pika Backup via Flatpak"

  if flatpak info "$FLATPAK_ID" &>/dev/null; then
    log "Pika Backup already installed (Flatpak)"
    return
  fi

  if ! flatpak remote-list | grep -q '^flathub'; then
    log "Adding Flathub remote"
    sudo flatpak remote-add --if-not-exists \
      flathub https://flathub.org/repo/flathub.flatpakrepo
  fi

  flatpak install -y flathub "$FLATPAK_ID"
}

config() {
  log "No configuration required"
}

clean() {
  log "Removing Pika Backup (Flatpak)"

  if flatpak info "$FLATPAK_ID" &>/dev/null; then
    flatpak uninstall -y "$FLATPAK_ID"
  else
    log "Pika Backup not installed"
  fi
}

case "$ACTION" in
all)
  deps
  install
  config
  ;;
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  die "Unknown action: $ACTION (use: all | deps | install | config | clean)"
  ;;
esac
