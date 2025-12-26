#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="discord"
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
FLATPAK_APP_ID="com.discordapp.Discord"
FLATHUB_REMOTE="flathub"
FLATHUB_URL="https://flathub.org/repo/flathub.flatpakrepo"

flatpak_app_installed() { # $1 = app id
  command -v flatpak &>/dev/null || return 1
  flatpak info --user "$1" &>/dev/null && return 0
  flatpak info --system "$1" &>/dev/null && return 0
  return 1
}

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

install_discord() {
  ensure_flathub

  # Check if Discord is installed via Flatpak (user or system)
  if flatpak_app_installed "$FLATPAK_APP_ID"; then
    log "Discord already installed (Flatpak)"
    return
  fi

  # If Discord is installed via RPM, don't force-install the Flatpak.
  if command -v discord &>/dev/null || rpm -q discord &>/dev/null; then
    log "Discord appears installed (RPM). Skipping Flatpak install."
    return
  fi

  log "Installing Discord via Flatpak"
  sudo flatpak install -y "$FLATHUB_REMOTE" "$FLATPAK_APP_ID"
}

configure_discord() {
  true
}

clean_discord() {
  log "Removing Discord Flatpak"
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
    install_discord
    ;;
  config)
    configure_discord
    ;;
  clean)
    clean_discord
    ;;
  all)
    install_deps
    install_discord
    configure_discord
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

log "Done: $ACTION"


