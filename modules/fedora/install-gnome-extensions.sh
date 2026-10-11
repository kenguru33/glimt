#!/usr/bin/env bash
# Glimt module: gnome-extensions
# Fedora Workstation
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="gnome-extensions"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

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

# --------------------------------------------------
# deps
# --------------------------------------------------
deps() {
  log "Installing dependencies"
  # gnome-extensions (the CLI) ships with gnome-shell itself
  dnf_ensure jq curl
}

# --------------------------------------------------
# install
# --------------------------------------------------
install() {
  log "Installing RPM-based GNOME extensions"
  dnf_ensure "${RPM_PACKAGES[@]}"

  if gnome-extensions list | grep -qx "$WEB_EXTENSION"; then
    log "Tiling Shell already installed"
    return
  fi

  log "Installing Tiling Shell from extensions.gnome.org"

  command -v gnome-shell >/dev/null || die "gnome-shell not found — cannot pick a compatible Tiling Shell version"

  local gnome_major meta pk info dl tmp_zip
  gnome_major="$(gnome-shell --version | awk '{print int($3)}')"
  meta="$(curl -fsSL \
    "https://extensions.gnome.org/extension-query/?search=${WEB_SEARCH}" |
    jq -r --arg u "$WEB_EXTENSION" '.extensions[] | select(.uuid==$u)')"

  [[ -n "$meta" ]] || die "Tiling Shell not found upstream"

  pk="$(jq -r '.pk' <<<"$meta")"

  info="$(curl -fsSL \
    "https://extensions.gnome.org/extension-info/?pk=${pk}&shell_version=${gnome_major}")"

  dl="$(jq -r '.download_url' <<<"$info")"
  [[ "$dl" != "null" ]] || die "No compatible Tiling Shell version for GNOME $gnome_major"

  tmp_zip="$(mktemp --suffix=.zip)"
  # remove the download even when curl/install fails (die/ERR exit the script)
  # shellcheck disable=SC2064  # expand $tmp_zip now, it is local
  trap "rm -f '$tmp_zip'" EXIT
  curl -fsSL "https://extensions.gnome.org${dl}" -o "$tmp_zip"
  gnome-extensions install --force "$tmp_zip"
  rm -f "$tmp_zip"
  trap - EXIT

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
