#!/usr/bin/env bash
# Glimt module: flatpak (Silverblue-correct)
#
# Actions:
#   all | install | config | clean
#
# Notes:
# - Flatpak is part of the Silverblue base image
# - We only manage the Flathub remote
# - Uses polkit (no sudo required when run interactively)

set -Eeuo pipefail

MODULE="flatpak"
ACTION="${1:-all}"

REMOTE_NAME="flathub"
REMOTE_URL="https://flathub.org/repo/flathub.flatpakrepo"

log() { echo "[$MODULE] $*"; }

# --------------------------------------------------
# OS guard (Fedora Silverblue)
# --------------------------------------------------
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  log "❌ Cannot detect OS"
  exit 1
fi

[[ "$ID" == "fedora" || "$ID_LIKE" == *fedora* ]] || {
  log "❌ Fedora Silverblue required"
  exit 1
}

command -v flatpak >/dev/null || {
  log "❌ Flatpak not available (unexpected on Silverblue)"
  exit 1
}

# --------------------------------------------------
# Install / enable Flathub
# --------------------------------------------------
enable_flathub() {
  if flatpak remotes --system | awk '{print $1}' | grep -qx "$REMOTE_NAME"; then
    log "✅ Flathub already enabled (system)"
    return 0
  fi

  log "🌐 Enabling Flathub (system-wide)"
  flatpak remote-add --system --if-not-exists "$REMOTE_NAME" "$REMOTE_URL"
  log "✅ Flathub enabled"
}

# --------------------------------------------------
# Remove Flathub
# --------------------------------------------------
remove_flathub() {
  if flatpak remotes --system | awk '{print $1}' | grep -qx "$REMOTE_NAME"; then
    log "🧹 Removing Flathub (system)"
    flatpak remote-delete --system "$REMOTE_NAME"
    log "✅ Flathub removed"
  else
    log "ℹ️ Flathub not present"
  fi
}

# --------------------------------------------------
# Dispatcher
# --------------------------------------------------
case "$ACTION" in
install|config|all)
  enable_flathub
  ;;
clean)
  remove_flathub
  ;;
*)
  echo "Usage: $0 {install|config|clean|all}"
  exit 1
  ;;
esac

exit 0
