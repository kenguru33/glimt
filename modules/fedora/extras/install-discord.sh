#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="discord"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

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

# ---- Flatpak / Flathub ----
FLATPAK_APP_ID="com.discordapp.Discord"
FLATHUB_REMOTE="flathub"
FLATHUB_URL="https://flathub.org/repo/flathub.flatpakrepo"

# Prints "user" or "system" for where the app is installed; fails if absent.
flatpak_app_scope() { # $1 = app id
  command -v flatpak &>/dev/null || return 1
  if flatpak info --user "$1" &>/dev/null; then echo user; return 0; fi
  if flatpak info --system "$1" &>/dev/null; then echo system; return 0; fi
  return 1
}

install_deps() {
  log "Installing Flatpak dependencies (dnf)…"
  dnf_ensure flatpak
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
  # Already installed: update it in the same scope (no-op when current)
  local scope
  if scope="$(flatpak_app_scope "$FLATPAK_APP_ID")"; then
    log "Discord already installed (Flatpak, $scope), checking for updates"
    if [[ "$scope" == user ]]; then
      run_as_user flatpak update -y --user "$FLATPAK_APP_ID" || warn "Discord update failed"
    else
      sudo flatpak update -y --system "$FLATPAK_APP_ID" || warn "Discord update failed"
    fi
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


