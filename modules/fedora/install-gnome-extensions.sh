#!/usr/bin/env bash
# Glimt module: gnome-extensions
# Fedora Workstation
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ gnome-extensions failed at line $LINENO" >&2' ERR

MODULE_NAME="gnome-extensions"
ACTION="${1:-all}"

# --------------------------------------------------
# Logging
# --------------------------------------------------
log()  { echo "🔧 [$MODULE_NAME] $*"; }
warn() { echo "⚠️  [$MODULE_NAME] $*" >&2; }
die()  { echo "❌ [$MODULE_NAME] $*" >&2; exit 1; }

# --------------------------------------------------
# Guards
# --------------------------------------------------
require_gnome() {
  command -v gnome-shell >/dev/null || die "GNOME not detected"
  [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || die "Run from GNOME session (not sudo / tty / ssh)"
}

# --------------------------------------------------
# Extensions
# --------------------------------------------------
RPM_PACKAGES=(
  gnome-shell-extension-blur-my-shell
  gnome-shell-extension-gsconnect
  gnome-shell-extension-appindicator
)

RPM_EXTENSIONS=(
  blur-my-shell@aunetx
  gsconnect@andyholmes.github.io
  appindicatorsupport@rgcjonas.gmail.com
)

WEB_EXTENSION="tilingshell@ferrarodomenico.com"
WEB_SEARCH="tiling-shell"

TMP_ZIP="$(mktemp)"
GNOME_MAJOR="$(gnome-shell --version | awk '{print int($3)}')"

# --------------------------------------------------
# deps
# --------------------------------------------------
deps() {
  log "Checking dependencies"

  command -v dnf >/dev/null || die "dnf not found"
  command -v gnome-extensions >/dev/null || die "gnome-extensions CLI missing"
  command -v curl >/dev/null || die "curl missing"
  command -v jq >/dev/null || die "jq missing"

  log "Dependencies OK"
}

# --------------------------------------------------
# install
# --------------------------------------------------
install() {
  log "Installing RPM-based GNOME extensions"
  sudo dnf install -y "${RPM_PACKAGES[@]}"

  if gnome-extensions list | grep -qx "$WEB_EXTENSION"; then
    log "Tiling Shell already installed"
    return
  fi

  log "Installing Tiling Shell from extensions.gnome.org"

  local meta pk info dl
  meta="$(curl -fsSL \
    "https://extensions.gnome.org/extension-query/?search=${WEB_SEARCH}" |
    jq -r --arg u "$WEB_EXTENSION" '.extensions[] | select(.uuid==$u)')"

  [[ -n "$meta" ]] || die "Tiling Shell not found upstream"

  pk="$(jq -r '.pk' <<<"$meta")"

  info="$(curl -fsSL \
    "https://extensions.gnome.org/extension-info/?pk=${pk}&shell_version=${GNOME_MAJOR}")"

  dl="$(jq -r '.download_url' <<<"$info")"
  [[ "$dl" != "null" ]] || die "No compatible Tiling Shell version for GNOME $GNOME_MAJOR"

  curl -fsSL "https://extensions.gnome.org${dl}" -o "$TMP_ZIP"
  gnome-extensions install --force "$TMP_ZIP"

  log "Tiling Shell installed"
}

# --------------------------------------------------
# config
# --------------------------------------------------
config() {
  require_gnome

  log "Enabling GNOME extensions"

  for ext in "${RPM_EXTENSIONS[@]}" "$WEB_EXTENSION"; do
    if gnome-extensions list | grep -qx "$ext"; then
      log "Enabling $ext"
      gnome-extensions enable "$ext" || true
    else
      warn "Extension not installed: $ext"
    fi
  done

  log "Configuration complete"
}

# --------------------------------------------------
# clean
# --------------------------------------------------
clean() {
  log "Removing GNOME extensions"

  sudo dnf remove -y "${RPM_PACKAGES[@]}" || true

  for ext in "${RPM_EXTENSIONS[@]}" "$WEB_EXTENSION"; do
    gnome-extensions disable "$ext" 2>/dev/null || true
    gnome-extensions uninstall "$ext" 2>/dev/null || true
  done

  log "Cleanup complete"
}

# --------------------------------------------------
# entrypoint
# --------------------------------------------------
case "$ACTION" in
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  all)
    deps
    install
    config
    ;;
  *)
    die "Unknown action: $ACTION (use: all | deps | install | config | clean)"
    ;;
esac

rm -f "$TMP_ZIP"
