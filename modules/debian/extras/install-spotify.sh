#!/usr/bin/env bash
# modules/debian/install-spotify.sh
# Glimt module: Install Spotify using Flatpak (Flathub)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="spotify"
ACTION="${1:-all}"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

# ---- Debian-only guard ----
deb_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || die "Debian-only module."
  else
    die "Cannot detect OS."
  fi
}

# ---- Flatpak / Flathub ----
FLATPAK_APP_ID="com.spotify.Client"
FLATHUB_REMOTE="flathub"
FLATHUB_URL="https://flathub.org/repo/flathub.flatpakrepo"

install_deps() {
  log "Installing Flatpak dependencies"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends flatpak ca-certificates
}

ensure_flathub() {
  if flatpak remote-list --columns=name | grep -qx "$FLATHUB_REMOTE"; then
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

  if flatpak info "$FLATPAK_APP_ID" &>/dev/null; then
    log "Spotify already installed (Flatpak)"
    return
  fi

  log "Installing Spotify via Flatpak"
  sudo flatpak install -y "$FLATHUB_REMOTE" "$FLATPAK_APP_ID"
}

configure_spotify() {
  # Placeholder for future tweaks:
  # - filesystem permissions
  # - PulseAudio / PipeWire overrides
  # - GPU / Wayland tweaks
  true
}

clean_spotify() {
  log "Removing Spotify Flatpak"
  sudo flatpak uninstall -y "$FLATPAK_APP_ID" || true

  log "Removing unused Flatpak runtimes"
  sudo flatpak uninstall -y --unused || true

  log "Clean complete."
}

# ---- Entry point ----
deb_guard

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
