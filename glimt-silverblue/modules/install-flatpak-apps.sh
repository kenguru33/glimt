#!/usr/bin/env bash
# Glimt module: flatpak-apps
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ flatpak-apps module failed at line $LINENO" >&2' ERR

MODULE_NAME="flatpak-apps"
ACTION="${1:-all}"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_user() {
  if [[ "$EUID" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    echo "❌ Do not run this module as root directly." >&2
    exit 1
  fi
}

# --------------------------------------------------
# Flatpak apps to install (USER scope)
# --------------------------------------------------
FLATPAK_APPS=(
  "com.spotify.Client"
  "com.discordapp.Discord"
)

# --------------------------------------------------
deps() {
  require_user

  command -v flatpak >/dev/null || {
    echo "❌ flatpak not installed (expected on Silverblue)"
    exit 1
  }

  # Ensure Flathub exists (USER scope)
  if ! flatpak --user remotes | awk '{print $1}' | grep -qx flathub; then
    log "➕ Adding Flathub remote (user)"
    flatpak --user remote-add --if-not-exists \
      flathub https://flathub.org/repo/flathub.flatpakrepo
  else
    log "✅ Flathub already configured (user)"
  fi
}

# --------------------------------------------------
install() {
  require_user

  log "📦 Installing Flatpak applications (user scope)"

  for app in "${FLATPAK_APPS[@]}"; do
    if flatpak --user list | awk '{print $1}' | grep -qx "$app"; then
      log "✅ $app already installed"
    else
      log "⬇️  Installing $app"
      flatpak install --user -y flathub "$app"
    fi
  done
}

# --------------------------------------------------
config() {
  require_user
  log "ℹ️ No additional configuration required"
}

# --------------------------------------------------
clean() {
  require_user

  log "🧹 Removing Flatpak applications (user scope)"

  for app in "${FLATPAK_APPS[@]}"; do
    if flatpak --user list | awk '{print $1}' | grep -qx "$app"; then
      flatpak uninstall --user -y "$app"
      log "❌ Removed $app"
    else
      log "ℹ️  $app not installed"
    fi
  done
}

# --------------------------------------------------
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
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac

exit 0
