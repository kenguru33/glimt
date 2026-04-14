#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="ptyxis-theme"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

# === GNOME session check ===
if [[ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
  echo "⏭️  GNOME not detected (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset})"
  echo "   Skipping Ptyxis configuration."
  exit 0
fi

# === deps ===
deps() {
  log "Checking dependencies..."
  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings not available. GNOME may not be installed."
  fi
  if ! command -v ptyxis >/dev/null 2>&1; then
    warn "ptyxis not found in PATH — theme will still be applied via gsettings."
  fi
}

# === install ===
install() {
  log "Applying Catppuccin Mocha theme to Ptyxis..."

  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings not available. Skipping."
    return 0
  fi

  local uuids_raw
  uuids_raw="$(run_as_user gsettings get org.gnome.Ptyxis profile-uuids 2>/dev/null || true)"

  if [[ -z "$uuids_raw" || "$uuids_raw" == "@as []" ]]; then
    warn "No Ptyxis profiles found. Is Ptyxis installed?"
    return 0
  fi

  # Parse ['uuid1', 'uuid2'] → one UUID per line
  local uuid
  while IFS= read -r uuid; do
    [[ -z "$uuid" ]] && continue
    run_as_user gsettings set \
      "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/${uuid}/" \
      palette 'Catppuccin Mocha'
    log "Set palette for profile ${uuid}"
  done < <(echo "$uuids_raw" | tr -d "[]' " | tr ',' '\n')

  run_as_user gsettings set org.gnome.Ptyxis interface-style 'dark'

  log "✅ Catppuccin Mocha applied to all Ptyxis profiles"
}

# === config ===
config() {
  log "No config files to deploy for Ptyxis theme."
}

# === clean ===
clean() {
  log "Resetting Ptyxis profiles to default palette..."

  if ! command -v gsettings >/dev/null 2>&1; then
    warn "gsettings not available."
    return 0
  fi

  local uuids_raw
  uuids_raw="$(run_as_user gsettings get org.gnome.Ptyxis profile-uuids 2>/dev/null || true)"

  if [[ -z "$uuids_raw" || "$uuids_raw" == "@as []" ]]; then
    return 0
  fi

  local uuid
  while IFS= read -r uuid; do
    [[ -z "$uuid" ]] && continue
    run_as_user gsettings reset \
      "org.gnome.Ptyxis.Profile:/org/gnome/Ptyxis/Profiles/${uuid}/" \
      palette
    log "Reset palette for profile ${uuid}"
  done < <(echo "$uuids_raw" | tr -d "[]' " | tr ',' '\n')

  run_as_user gsettings reset org.gnome.Ptyxis interface-style

  log "✅ Ptyxis profiles reset"
}

# === Entry Point ===
case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
