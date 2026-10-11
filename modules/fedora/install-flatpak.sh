#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="flatpak"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

REMOTE_NAME="flathub"
REMOTE_URL="https://flathub.org/repo/flathub.flatpakrepo"

# === OS Check (Fedora only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "Error: Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "Error: This module supports Fedora/RHEL-based systems only."
  exit 1
fi

has_remote() {
  flatpak remote-list --columns=name 2>/dev/null | grep -qx "$REMOTE_NAME"
}

install_deps() {
  log "Installing Flatpak..."
  dnf_ensure flatpak
}

install_flatpak() {
  log "Setting up Flathub remote..."
  if ! has_remote; then
    log "Adding Flathub remote..."
    sudo flatpak remote-add --if-not-exists "$REMOTE_NAME" "$REMOTE_URL"
  else
    log "Flathub remote already added."
  fi
}

config_flatpak() {
  log "Ensuring Flathub is set up..."
  if ! has_remote; then
    sudo flatpak remote-add --if-not-exists "$REMOTE_NAME" "$REMOTE_URL"
  fi
  log "Flatpak is configured with Flathub."
}

# Flatpak itself is a preinstalled system component on Fedora Workstation
# (GNOME Software depends on it), so clean only removes the remote glimt added.
clean_flatpak() {
  log "Removing Flathub remote..."
  if command -v flatpak >/dev/null 2>&1 && has_remote; then
    if sudo flatpak remote-delete "$REMOTE_NAME"; then
      log "Flathub remote removed (flatpak itself is left installed)."
    else
      warn "Could not remove the $REMOTE_NAME remote (apps still installed from it?)"
    fi
  else
    log "ℹ️  Flathub remote not configured — nothing to clean"
  fi
}

# === Entry point ===
case "$ACTION" in
deps)
  install_deps
  ;;
install)
  install_flatpak
  ;;
config)
  config_flatpak
  ;;
clean)
  clean_flatpak
  ;;
all)
  install_deps
  install_flatpak
  config_flatpak
  ;;
*)
  die "Unknown action: $ACTION (use: all | deps | install | config | clean)"
  ;;
esac
