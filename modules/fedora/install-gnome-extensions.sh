#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_NAME="gnome-extensions"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
EXT_DIR="$HOME_DIR/.local/share/gnome-shell/extensions"
TMP_ZIP="/tmp/gnome-ext.zip"

# GNOME MAJOR VERSION ONLY (e.g. 45, 46, 47, 49)
GNOME_VERSION="$(gnome-shell --version | awk '{print int($3)}')"

EXTENSIONS=(
  "blur-my-shell@aunetx"
  "tilingshell@ferrarodomenico.com"
  "appindicatorsupport@rgcjonas.gmail.com"
)

log() {
  echo "[$MODULE_NAME] $*"
}

die() {
  echo "❌ [$MODULE_NAME] $*" >&2
  exit 1
}

# --------------------------------------------------
# GNOME session guard (LOCAL, QUIET)
# --------------------------------------------------
if [[ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
  log "GNOME not detected – skipping"
  exit 0
fi

# --------------------------------------------------
# OS detection (Fedora only)
# --------------------------------------------------
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  die "Cannot detect OS"
fi

if [[ "$ID" != "fedora" && "${ID_LIKE:-}" != *fedora* ]]; then
  die "This script supports Fedora only"
fi

# --------------------------------------------------
# Dependencies
# --------------------------------------------------
DEPS=(curl unzip jq gnome-extensions-app glib2)

install_deps() {
  sudo dnf install -y "${DEPS[@]}"
}

# --------------------------------------------------
# GSettings helpers (SCHEMA-SAFE)
# --------------------------------------------------
has_schema() {
  gsettings list-schemas 2>/dev/null | grep -qx "$1"
}

gs_set_safe() {
  local schema="$1"
  shift

  if has_schema "$schema"; then
    gsettings set "$schema" "$@" >/dev/null 2>&1 || true
  fi
}

# --------------------------------------------------
# Extension helpers
# --------------------------------------------------
enable_extension_safe() {
  local uuid="$1"

  if gnome-extensions list | grep -q "$uuid"; then
    gnome-extensions enable "$uuid" >/dev/null 2>&1 || true
  fi
}

reload_notice() {
  log "Extensions installed."
  log "Log out and back in to complete activation."
}

# --------------------------------------------------
# Install extensions
# --------------------------------------------------
install_extensions() {
  log "Installing GNOME extensions…"
  mkdir -p "$EXT_DIR"

  for EXT_ID in "${EXTENSIONS[@]}"; do
    log "Processing $EXT_ID"

    if [[ "$EXT_ID" == "tilingshell@ferrarodomenico.com" ]]; then
      SEARCH="tiling-shell"
    else
      SEARCH="$EXT_ID"
    fi

    METADATA="$(curl -fsSL \
      "https://extensions.gnome.org/extension-query/?search=${SEARCH}" |
      jq -r --arg uuid "$EXT_ID" '.extensions[] | select(.uuid == $uuid)')"

    [[ -z "$METADATA" ]] && continue

    PK_ID="$(echo "$METADATA" | jq -r '.pk')"

    VERSION_JSON="$(curl -fsSL \
      "https://extensions.gnome.org/extension-info/?pk=${PK_ID}&shell_version=${GNOME_VERSION}")"

    DL_PATH="$(echo "$VERSION_JSON" | jq -r '.download_url')"
    [[ "$DL_PATH" == "null" ]] && continue

    DL_URL="https://extensions.gnome.org${DL_PATH}"
    curl -fsSL "$DL_URL" -o "$TMP_ZIP"

    TMP_DIR="$(mktemp -d)"
    unzip -oq "$TMP_ZIP" -d "$TMP_DIR"

    METADATA_JSON="$(find "$TMP_DIR" -name metadata.json | head -n1)"
    [[ -z "$METADATA_JSON" ]] && continue

    ACTUAL_UUID="$(jq -r '.uuid' "$METADATA_JSON")"
    DEST="$EXT_DIR/$ACTUAL_UUID"

    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp -r "$(dirname "$METADATA_JSON")"/* "$DEST"

    if [[ -d "$DEST/schemas" ]]; then
      glib-compile-schemas "$DEST/schemas" >/dev/null 2>&1 || true
    fi

    enable_extension_safe "$ACTUAL_UUID"
  done

  reload_notice
}

# --------------------------------------------------
# Configure extensions (QUIET, NON-FATAL)
# --------------------------------------------------
config_extensions() {
  log "Configuring GNOME extensions…"

  # Blur My Shell
  gs_set_safe org.gnome.shell.extensions.blur-my-shell brightness 0.8
  gs_set_safe org.gnome.shell.extensions.blur-my-shell sigma 30
  gs_set_safe org.gnome.shell.extensions.blur-my-shell color-and-noise true
  gs_set_safe org.gnome.shell.extensions.blur-my-shell hacks-level 1

  # AppIndicator
  gs_set_safe org.gnome.shell.extensions.appindicator use-symbolic-icons true

  # Tiling Shell → no schema → intentionally skipped
}

# --------------------------------------------------
# Dispatcher
# --------------------------------------------------
case "$ACTION" in
deps)
  install_deps
  ;;
install)
  install_extensions
  ;;
config)
  config_extensions
  ;;
all)
  install_deps
  install_extensions
  config_extensions
  ;;
*)
  echo "Usage: $0 [deps|install|config|all]"
  exit 1
  ;;
esac
