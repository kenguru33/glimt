#!/usr/bin/env bash
# modules/fedora/extras/install-ytmusic.sh
# YouTube Music PWA (Chrome/Chromium/Brave) — Fedora only
# Actions: all | deps | install | config | clean
set -Eeuo pipefail
trap 'echo "ERROR at line $LINENO: $BASH_COMMAND" >&2' ERR

MODULE_NAME="ytmusic-pwa"
ACTION="${1:-all}"

log(){ printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

# --- Fedora-only guard ---
if [[ -r /etc/os-release ]]; then . /etc/os-release; else die "Cannot detect OS."; fi
[[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || die "Fedora-only module."

# --- App metadata ---
APP_NAME="YouTube Music"
APP_URL="https://music.youtube.com"
APP_ID="ytmusic-ssb"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

LAUNCHER_DIR="$HOME_DIR/.local/share/applications"
APP_DIR="$HOME_DIR/.local/share/ytmusic-pwa"
PROFILE_DIR="$HOME_DIR/.local/share/ytmusic-chrome-profile"
DESKTOP_FILE="$LAUNCHER_DIR/${APP_ID}.desktop"

# Icon files (absolute path in .desktop)
ICON_PNG="$APP_DIR/icon.png"
ICON_SVG="$APP_DIR/icon.svg"

# Also install into the user hicolor theme (secondary, best-effort)
HICOLOR="$HOME_DIR/.local/share/icons/hicolor"

# CLI
BIN_DIR="$HOME_DIR/.local/bin"
CLI_WRAPPER="$BIN_DIR/ytmusic"
CLI_ALIAS="$BIN_DIR/ytm"

# Official icon source (Wikimedia Commons)
ICON_SRC_SVG="https://upload.wikimedia.org/wikipedia/commons/6/6a/Youtube_Music_icon.svg"

# -------------------------------
# Deps
# -------------------------------
install_deps(){
  log "Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y curl wget xdg-utils desktop-file-utils librsvg2-tools
}

# -------------------------------
# Icon (official) — MUST succeed
# -------------------------------
download_file(){ # $1=url $2=dest
  local url="$1" dest="$2"
  # Use curl first (follows redirects), then wget
  if command -v curl >/dev/null 2>&1; then
    sudo -u "$REAL_USER" curl -fsSL --retry 3 --retry-delay 1 -o "$dest" "$url" && return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    sudo -u "$REAL_USER" wget -q -T 30 --tries=3 -O "$dest" "$url" && return 0
  fi
  return 1
}

fetch_official_icon(){
  sudo -u "$REAL_USER" mkdir -p "$APP_DIR"

  # Try to download SVG and convert to PNG
  if download_file "$ICON_SRC_SVG" "$ICON_SVG" && [[ -s "$ICON_SVG" ]]; then
    if command -v rsvg-convert >/dev/null 2>&1; then
      sudo -u "$REAL_USER" rsvg-convert -w 256 -h 256 "$ICON_SVG" -o "$ICON_PNG" || true
      if [[ -s "$ICON_PNG" ]]; then
        log "YouTube Music icon SVG downloaded and converted to PNG."
        return 0
      fi
    else
      die "librsvg2-tools (rsvg-convert) missing — cannot convert SVG to PNG."
    fi
  fi

  die "Failed to obtain the YouTube Music icon."
}

install_theme_icons(){
  # Best-effort: register in hicolor so the name could also work if you switch to Icon=ytmusic-ssb
  sudo -u "$REAL_USER" mkdir -p "$HICOLOR"/{16x16,24x24,32x32,48x48,64x64,128x128,256x256}/apps
  local base="$ICON_PNG"; [[ -r "$ICON_SVG" ]] && base="$ICON_SVG"
  if command -v rsvg-convert >/dev/null 2>&1 && [[ "$base" == "$ICON_SVG" ]]; then
    local sizes=(16 24 32 48 64 128 256)
    for s in "${sizes[@]}"; do
      sudo -u "$REAL_USER" rsvg-convert -w "$s" -h "$s" "$ICON_SVG" -o "$HICOLOR/${s}x${s}/apps/${APP_ID}.png" || true
    done
  else
    sudo -u "$REAL_USER" cp -f "$ICON_PNG" "$HICOLOR/256x256/apps/${APP_ID}.png" || true
  fi
  command -v gtk-update-icon-cache >/dev/null 2>&1 && sudo -u "$REAL_USER" gtk-update-icon-cache -f -t "$HICOLOR" || true
}

# -------------------------------
# CLI launcher
# -------------------------------
write_cli_wrapper(){
  sudo -u "$REAL_USER" mkdir -p "$BIN_DIR" "$PROFILE_DIR"
  cat >"$CLI_WRAPPER" <<'EOSH'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_URL="https://music.youtube.com"
APP_ID="ytmusic-ssb"
PROFILE_DIR="${HOME}/.local/share/ytmusic-chrome-profile"

detect_browser() {
  local c
  for c in google-chrome-stable google-chrome chromium chromium-browser brave-browser; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "$c"; return 0
    fi
  done
  return 1
}

BROWSER="$(detect_browser || true)"
if [[ -z "${BROWSER:-}" ]]; then
  echo "ytmusic: No supported browser (Chrome/Chromium/Brave) found." >&2
  exit 127
fi

force_x11="${YTMUSIC_FORCE_X11:-1}"
declare -a ENV_PREFIX=()
declare -a BFLAGS=(--no-first-run --no-default-browser-check --disable-sync --disable-extensions
  "--user-data-dir=${PROFILE_DIR}" "--class=${APP_ID}" "--app=${APP_URL}")

if [[ "${XDG_SESSION_TYPE:-}" == "wayland" && "$force_x11" == "1" ]]; then
  ENV_PREFIX=(env GDK_BACKEND=x11 XDG_SESSION_TYPE=x11)
  BFLAGS+=("--ozone-platform=x11")
else
  BFLAGS+=("--enable-features=UseOzonePlatform,WaylandWindowDecorations" "--ozone-platform=wayland")
fi

exec "${ENV_PREFIX[@]}" "$BROWSER" "${BFLAGS[@]}" "$@"
EOSH
  sudo -u "$REAL_USER" chmod 0755 "$CLI_WRAPPER"
  sudo -u "$REAL_USER" ln -sf "$CLI_WRAPPER" "$CLI_ALIAS"
  log "CLI installed: $(basename "$CLI_WRAPPER") (alias: $(basename "$CLI_ALIAS"))"
}

# -------------------------------
# Desktop launcher
# -------------------------------
write_desktop(){
  sudo -u "$REAL_USER" mkdir -p "$LAUNCHER_DIR"

  fetch_official_icon
  install_theme_icons

  # Use the absolute PNG path (most reliable)
  local icon_field="$ICON_PNG"

  cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=Play music from YouTube Music
Exec=$CLI_WRAPPER
TryExec=$CLI_WRAPPER
StartupNotify=false
Terminal=false
Icon=$icon_field
Categories=Audio;Music;Player;GTK;
Keywords=music;audio;youtube;yt;stream;
StartupWMClass=$APP_ID
DBusActivatable=false
X-GNOME-UsesNotifications=true
EOF
  sudo -u "$REAL_USER" chmod 0644 "$DESKTOP_FILE"
  log "Wrote $DESKTOP_FILE (Icon=$icon_field)"
}

# -------------------------------
# Config / Clean / Install
# -------------------------------
configure(){
  command -v update-desktop-database >/dev/null 2>&1 && sudo -u "$REAL_USER" update-desktop-database "$LAUNCHER_DIR" || true
  case ":$PATH:" in *":$HOME_DIR/.local/bin:"*) ;; *)
    log "Note: add '\$HOME_DIR/.local/bin' to PATH to use 'ytmusic'/'ytm' from the terminal." ;;
  esac
  log "Done."
}

clean(){
  log "Removing launcher, icon and CLI..."
  sudo -u "$REAL_USER" rm -f "$DESKTOP_FILE"
  sudo -u "$REAL_USER" rm -rf "$APP_DIR"
  sudo -u "$REAL_USER" rm -f "$CLI_WRAPPER" "$CLI_ALIAS"
  sudo -u "$REAL_USER" rm -rf "$PROFILE_DIR"
  sudo -u "$REAL_USER" rm -f "$HICOLOR"/{16x16,24x24,32x32,48x48,64x64,128x128,256x256}/apps/"${APP_ID}.png" || true
  command -v gtk-update-icon-cache >/dev/null 2>&1 && sudo -u "$REAL_USER" gtk-update-icon-cache -f -t "$HICOLOR" || true
}

do_install(){
  write_cli_wrapper
  write_desktop
}

# -------------------------------
# Entry
# -------------------------------
case "$ACTION" in
  deps)    install_deps ;;
  install) do_install ;;
  config)  configure ;;
  clean)   clean ;;
  all)     install_deps; do_install; configure ;;
  *)       die "Unknown action: $ACTION (use: all|deps|install|config|clean)" ;;
esac

