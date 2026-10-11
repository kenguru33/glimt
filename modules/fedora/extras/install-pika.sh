#!/usr/bin/env bash
# Glimt module: Install Pika Backup (Flatpak)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="pika-backup"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

FLATPAK_ID="org.gnome.World.PikaBackup"
ACTION="${1:-all}"

# ---- Fedora-only guard ----
fedora_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "${ID:-}" == "fedora" || "${ID_LIKE:-}" == *"fedora"* || "${ID:-}" == "rhel" ]] || die "Fedora/RHEL-only module."
  else
    die "Cannot detect OS."
  fi
}

deps() {
  log "Ensuring Flatpak is available"
  if ! command -v flatpak >/dev/null 2>&1; then
    sudo dnf install -y flatpak
  fi
}

# Exact name match: `grep '^flathub'` would also accept e.g. flathub-beta
flathub_configured() {
  flatpak remotes --columns=name 2>/dev/null | grep -qx flathub
}

install() {
  log "Installing Pika Backup via Flatpak"

  if flatpak info "$FLATPAK_ID" &>/dev/null; then
    log "Pika Backup already installed (Flatpak)"
    return
  fi

  if ! flathub_configured; then
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

fedora_guard

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
