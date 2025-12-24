#!/usr/bin/env bash
# modules/install-outlook-pwa.sh
# Outlook Web PWA (Chrome/Chromium) — Fedora only
# Actions: all | deps | install | config | clean
set -Eeuo pipefail
trap 'echo "ERROR at line $LINENO: $BASH_COMMAND" >&2' ERR

MODULE_NAME="outlook-pwa"
ACTION="${1:-all}"

log(){ printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

# --- Fedora-only guard ---
if [[ -r /etc/os-release ]]; then . /etc/os-release; else die "Cannot detect OS."; fi
[[ "${ID:-}" == "fedora" || "${ID_LIKE:-}" == *"fedora"* || "$ID" == "rhel" ]] || die "Fedora/RHEL-only module."

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

# --- App metadata ---
APP_NAME="Outlook"
# For personal accounts: export OUTLOOK_URL=https://outlook.live.com/mail/
APP_URL="${OUTLOOK_URL:-https://outlook.office.com/mail/}"
APP_ID="outlook-ssb"

LAUNCHER_DIR="$HOME_DIR/.local/share/applications"
APP_DIR="$HOME_DIR/.local/share/outlook-pwa"
PROFILE_DIR="$HOME_DIR/.local/share/outlook-chrome-profile"
DESKTOP_FILE="$LAUNCHER_DIR/${APP_ID}.desktop"

# Icon files (absolute path in .desktop)
ICON_PNG="$APP_DIR/outlook.png"
ICON_SVG="$APP_DIR/outlook.svg"

# Also install into the user hicolor theme (secondary, best-effort)
HICOLOR="$HOME_DIR/.local/share/icons/hicolor"

# CLI
BIN_DIR="$HOME_DIR/.local/bin"
CLI_WRAPPER="$BIN_DIR/outlook"
CLI_ALIAS="$BIN_DIR/ol"

# --- Official icon sources (Wikimedia Commons) ---
# Use Special:FilePath to avoid brittle /upload/ paths and encoded characters.
# Primary (2018–present):
OFFICIAL_SVG_MAIN="https://commons.wikimedia.org/wiki/Special:FilePath/Microsoft_Office_Outlook_(2018%E2%80%93present).svg"
OFFICIAL_PNG256_MAIN="https://commons.wikimedia.org/wiki/Special:FilePath/Microsoft_Office_Outlook_(2018%E2%80%93present).svg?width=256"
# Alternate new logo (also official):
OFFICIAL_SVG_ALT="https://commons.wikimedia.org/wiki/Special:FilePath/Microsoft_Outlook_new_logo.svg"

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
    curl -fsSL --retry 3 --retry-delay 1 -o "$dest" "$url" && return 0
  fi
  if command -v wget >/dev/null 2>&1; then
    wget -q -T 30 --tries=3 -O "$dest" "$url" && return 0
  fi
  return 1
}

fetch_official_icon(){
  sudo -u "$REAL_USER" mkdir -p "$APP_DIR"

  # 1) Try direct PNG rasterized by Commons at 256px
  if download_file "$OFFICIAL_PNG256_MAIN" "$ICON_PNG" && [[ -s "$ICON_PNG" ]]; then
    chown "$REAL_USER:$REAL_USER" "$ICON_PNG"
    log "Official Outlook PNG (256px) downloaded via Special:FilePath."
    return 0
  fi

  # 2) Try official SVGs, then convert to PNG
  local svg_candidates=(
    "$OFFICIAL_SVG_MAIN"
    "$OFFICIAL_SVG_ALT"
  )

  for u in "${svg_candidates[@]}"; do
    rm -f "$ICON_SVG"
    if download_file "$u" "$ICON_SVG" && [[ -s "$ICON_SVG" ]]; then
      chown "$REAL_USER:$REAL_USER" "$ICON_SVG"
      if command -v rsvg-convert >/dev/null 2>&1; then
        rsvg-convert -w 256 -h 256 "$ICON_SVG" -o "$ICON_PNG" || true
        chown "$REAL_USER:$REAL_USER" "$ICON_PNG"
        if [[ -s "$ICON_PNG" ]]; then
          log "Official Outlook SVG fetched and converted to PNG."
          return 0
        fi
      else
        die "librsvg2-tools (rsvg-convert) missing — cannot convert official SVG to PNG."
      fi
    fi
  done

  die "Failed to obtain the official Outlook icon (both PNG and SVG sources failed)."
}

install_theme_icons(){
  # Best-effort: register in hicolor so the name could also work if you switch to Icon=outlook-ssb
  sudo -u "$REAL_USER" mkdir -p "$HICOLOR"/{16x16,24x24,32x32,48x48,64x64,128x128,256x256}/apps
  if command -v rsvg-convert >/dev/null 2>&1 && [[ -r "$ICON_SVG" ]]; then
    # Use SVG if available for better scaling
    local sizes=(16 24 32 48 64 128 256)
    for s in "${sizes[@]}"; do
      rsvg-convert -w "$s" -h "$s" "$ICON_SVG" -o "$HICOLOR/${s}x${s}/apps/${APP_ID}.png" || true
      chown "$REAL_USER:$REAL_USER" "$HICOLOR/${s}x${s}/apps/${APP_ID}.png" 2>/dev/null || true
    done
  else
    # Fallback: just copy the PNG to 256x256
    cp -f "$ICON_PNG" "$HICOLOR/256x256/apps/${APP_ID}.png" || true
    chown "$REAL_USER:$REAL_USER" "$HICOLOR/256x256/apps/${APP_ID}.png" 2>/dev/null || true
  fi
  command -v gtk-update-icon-cache >/dev/null 2>&1 && sudo -u "$REAL_USER" gtk-update-icon-cache -f -t "$HICOLOR" || true
}

# -------------------------------
# CLI launcher
# -------------------------------
write_cli_wrapper(){
  sudo -u "$REAL_USER" mkdir -p "$BIN_DIR" "$PROFILE_DIR"
  sudo -u "$REAL_USER" cat >"$CLI_WRAPPER" <<'EOSH'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_URL="${OUTLOOK_URL:-https://outlook.office.com/mail/}"
APP_ID="outlook-ssb"
PROFILE_DIR="${HOME}/.local/share/outlook-chrome-profile"

detect_browser() {
  local c
  for c in google-chrome-stable google-chrome chromium chromium-browser; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "$c"; return 0
    fi
  done
  return 1
}

BROWSER="$(detect_browser || true)"
if [[ -z "${BROWSER:-}" ]]; then
  echo "outlook: No supported browser (Chrome/Chromium) found." >&2
  exit 127
fi

force_x11="${OUTLOOK_FORCE_X11:-1}"
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
  chmod 0755 "$CLI_WRAPPER"
  chown "$REAL_USER:$REAL_USER" "$CLI_WRAPPER"
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

  sudo -u "$REAL_USER" cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=Outlook Web as a standalone app
Exec=$CLI_WRAPPER
TryExec=$CLI_WRAPPER
StartupNotify=false
Terminal=false
Icon=$icon_field
Categories=Office;Email;Network;GTK;
Keywords=mail;email;outlook;exchange;office365;microsoft;
StartupWMClass=$APP_ID
DBusActivatable=false
X-GNOME-UsesNotifications=true
EOF
  chmod 0644 "$DESKTOP_FILE"
  chown "$REAL_USER:$REAL_USER" "$DESKTOP_FILE"
  log "Wrote $DESKTOP_FILE (Icon=$icon_field)"
}

# -------------------------------
# Config / Clean / Install
# -------------------------------
configure(){
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$LAUNCHER_DIR" >/dev/null 2>&1 || true
  case ":$PATH:" in *":$HOME_DIR/.local/bin:"*) ;; *)
    log "Note: add '\$HOME/.local/bin' to PATH to use 'outlook'/'ol' from the terminal." ;;
  esac
  log "Done."
}

clean(){
  log "Removing launcher, icon and CLI..."
  sudo -u "$REAL_USER" rm -f "$DESKTOP_FILE"
  sudo -u "$REAL_USER" rm -rf "$APP_DIR"
  sudo -u "$REAL_USER" rm -f "$CLI_WRAPPER" "$CLI_ALIAS"
  sudo -u "$REAL_USER" rm -rf "$PROFILE_DIR"
  sudo -u "$REAL_USER" rm -f "$HICOLOR"/{16x16,24x24,32x32,48x48,64x64,128x128,256x256}/apps/"${APP_ID}.png" 2>/dev/null || true
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

