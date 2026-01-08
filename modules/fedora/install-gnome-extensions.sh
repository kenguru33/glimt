#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_NAME="gnome-extensions"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
EXT_DIR="$HOME_DIR/.local/share/gnome-shell/extensions"
TMP_ZIP="/tmp/gnome-ext.zip"

# GNOME MAJOR VERSION ONLY (49, ikke 49.x)
GNOME_VERSION="$(gnome-shell --version | awk '{print int($3)}')"

EXTENSIONS=(
  "blur-my-shell@aunetx"
  "tilingshell@ferrarodomenico.com"
  "appindicatorsupport@rgcjonas.gmail.com"
)

log() { echo "[$MODULE_NAME] $*"; }
die() {
  echo "❌ $*" >&2
  exit 1
}

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
DEPS=(curl unzip jq gnome-extensions-app dconf glib2)

install_deps() {
  log "Installing dependencies..."
  sudo dnf install -y "${DEPS[@]}"
}

# --------------------------------------------------
# Helpers
# --------------------------------------------------
enable_extension_safe() {
  local uuid="$1"

  if sudo -u "$REAL_USER" gnome-extensions list | grep -q "$uuid"; then
    sudo -u "$REAL_USER" gnome-extensions enable "$uuid" || true
    log "Enabled $uuid"
  else
    log "Extension $uuid not registered yet (will enable after login)"
  fi
}

reload_notice() {
  echo
  echo "🔁 Extensions installed."
  echo "🚨 Log out and back in to complete activation."
  echo
}

# --------------------------------------------------
# Install extensions
# --------------------------------------------------
install_extensions() {
  log "Installing GNOME extensions..."
  sudo -u "$REAL_USER" mkdir -p "$EXT_DIR"

  for EXT_ID in "${EXTENSIONS[@]}"; do
    log "Processing $EXT_ID"

    # Fedora backend does not index Tiling Shell UUID
    if [[ "$EXT_ID" == "tilingshell@ferrarodomenico.com" ]]; then
      SEARCH="tiling-shell"
    else
      SEARCH="$EXT_ID"
    fi

    METADATA="$(curl -fsSL \
      "https://extensions.gnome.org/extension-query/?search=${SEARCH}" |
      jq -r --arg uuid "$EXT_ID" '.extensions[] | select(.uuid == $uuid)')"

    if [[ -z "$METADATA" ]]; then
      log "Extension $EXT_ID not found"
      continue
    fi

    PK_ID="$(echo "$METADATA" | jq -r '.pk')"

    VERSION_JSON="$(curl -fsSL \
      "https://extensions.gnome.org/extension-info/?pk=${PK_ID}&shell_version=${GNOME_VERSION}")"

    DL_PATH="$(echo "$VERSION_JSON" | jq -r '.download_url')"

    if [[ "$DL_PATH" == "null" ]]; then
      log "No compatible version for GNOME $GNOME_VERSION"
      continue
    fi

    DL_URL="https://extensions.gnome.org${DL_PATH}"

    log "Downloading $EXT_ID (GNOME $GNOME_VERSION)"
    curl -fsSL "$DL_URL" -o "$TMP_ZIP"

    TMP_DIR="$(mktemp -d)"
    unzip -oq "$TMP_ZIP" -d "$TMP_DIR"

    METADATA_JSON="$(find "$TMP_DIR" -name metadata.json | head -n1)"
    [[ -z "$METADATA_JSON" ]] && die "metadata.json not found for $EXT_ID"

    ACTUAL_UUID="$(jq -r '.uuid' "$METADATA_JSON")"
    DEST="$EXT_DIR/$ACTUAL_UUID"

    log "Installing to $DEST"
    sudo -u "$REAL_USER" rm -rf "$DEST"
    sudo -u "$REAL_USER" mkdir -p "$DEST"
    sudo -u "$REAL_USER" cp -r "$(dirname "$METADATA_JSON")"/* "$DEST"

    if [[ -d "$DEST/schemas" ]]; then
      log "Compiling schemas for $ACTUAL_UUID"
      sudo -u "$REAL_USER" glib-compile-schemas "$DEST/schemas"
    fi

    enable_extension_safe "$ACTUAL_UUID"
  done

  reload_notice
}

# --------------------------------------------------
# Configure extensions
# --------------------------------------------------
config_extensions() {
  log "Configuring extensions..."

  log "Blur My Shell"
  sudo -u "$REAL_USER" gsettings set \
    org.gnome.shell.extensions.blur-my-shell brightness 0.8
  sudo -u "$REAL_USER" gsettings set \
    org.gnome.shell.extensions.blur-my-shell sigma 30
  sudo -u "$REAL_USER" gsettings set \
    org.gnome.shell.extensions.blur-my-shell color-and-noise true
  sudo -u "$REAL_USER" gsettings set \
    org.gnome.shell.extensions.blur-my-shell hacks-level 1

  log "AppIndicator"
  sudo -u "$REAL_USER" gsettings set \
    org.gnome.shell.extensions.appindicator use-symbolic-icons true

  log "Tiling Shell"
  log "Tiling Shell has NO GSettings schema"
  log "Configure via UI:"
  log "  gnome-extensions prefs tilingshell@ferrarodomenico.com"
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
