#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="spotify"
ACTION="${1:-all}"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

# ---- Fedora-only guard ----
fedora_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || die "Fedora/RHEL-only module."
  else
    die "Cannot detect OS."
  fi
}

# ---- Flatpak / Flathub ----
FLATPAK_APP_ID="com.spotify.Client"
FLATHUB_REMOTE="flathub"
FLATHUB_URL="https://flathub.org/repo/flathub.flatpakrepo"

install_deps() {
  log "Installing Flatpak dependencies (dnf)…"
  sudo dnf makecache -y
  sudo dnf install -y flatpak
}

ensure_flathub() {
  if ! command -v flatpak &>/dev/null; then
    log "Flatpak not found. Installing..."
    install_deps
  fi

  if flatpak remote-list --columns=name 2>/dev/null | grep -qx "$FLATHUB_REMOTE"; then
    log "Flathub remote already configured"
  else
    log "Adding Flathub remote"
    sudo flatpak remote-add --if-not-exists \
      "$FLATHUB_REMOTE" \
      "$FLATHUB_URL"
  fi
}

install_spotify() {
  ensure_flathub

  # Check if Spotify is installed via Flatpak
  if command -v flatpak &>/dev/null && flatpak info "$FLATPAK_APP_ID" &>/dev/null; then
    log "Spotify already installed (Flatpak)"
    return
  fi

  log "Installing Spotify via Flatpak"
  sudo flatpak install -y "$FLATHUB_REMOTE" "$FLATPAK_APP_ID"
}

configure_spotify() {
  true
}

clean_spotify() {
  log "Removing Spotify Flatpak"
  if command -v flatpak &>/dev/null; then
    sudo flatpak uninstall -y "$FLATPAK_APP_ID" || true

    log "Removing unused Flatpak runtimes"
    sudo flatpak uninstall -y --unused || true
  fi

  log "Clean complete."
}

# ---- Entry point ----
fedora_guard

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    install_spotify
    ;;
  config)
    configure_spotify
    ;;
  clean)
    clean_spotify
    ;;
  all)
    install_deps
    install_spotify
    configure_spotify
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

log "Done: $ACTION"


