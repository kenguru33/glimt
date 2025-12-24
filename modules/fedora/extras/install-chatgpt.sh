#!/usr/bin/env bash
# modules/fedora/extras/install-chatgpt.sh
# ChatGPT Web launcher (Chrome/Chromium/Brave) — Fedora only
# Uses the ChatGPT icon from Wikipedia (Wikimedia Commons),
# renders it onto a rounded white card, and cache-busts the filename.
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "ERROR at line $LINENO: $BASH_COMMAND" >&2' ERR

MODULE_NAME="chatgpt-pwa"
ACTION="${1:-all}"

log(){ printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

# --- Fedora-only guard ---
if [[ -r /etc/os-release ]]; then . /etc/os-release; else die "Cannot detect OS."; fi
[[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || die "Fedora-only module."

# --- App metadata ---
APP_NAME="ChatGPT"
APP_URL="${CHATGPT_URL:-https://chatgpt.com/}"   # override with CHATGPT_URL=...
APP_ID="chatgpt-ssb"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

LAUNCHER_DIR="$HOME_DIR/.local/share/applications"
APP_DIR="$HOME_DIR/.local/share/chatgpt-pwa"
PROFILE_DIR="$HOME_DIR/.local/share/chatgpt-chrome-profile"
DESKTOP_FILE="$LAUNCHER_DIR/${APP_ID}.desktop"

# Icon workspace
ICON_SVG="$APP_DIR/chatgpt.svg"
ICON_RAW="$APP_DIR/chatgpt-raw.png"   # what we fetch/rasterize first
ICON_TMP="$APP_DIR/.icon.tmp"
MASK="$APP_DIR/.mask.png"
CARD="$APP_DIR/.card.png"
INNER="$APP_DIR/.inner.png"

# CLI
BIN_DIR="$HOME_DIR/.local/bin"
CLI_WRAPPER="$BIN_DIR/chatgpt"
CLI_ALIAS="$BIN_DIR/cgpt"

# Wikipedia (Wikimedia Commons) icon sources
# You can override with: CHATGPT_WIKI_ICON_URL="https://commons.wikimedia.org/wiki/Special:FilePath/ChatGPT-Logo.svg"
WIKI_SVG_CANDIDATE="${CHATGPT_WIKI_ICON_URL:-}"
WIKI_SVG_LIST=(
  "https://commons.wikimedia.org/wiki/Special:FilePath/ChatGPT-Logo.svg"
  "https://commons.wikimedia.org/wiki/Special:FilePath/ChatGPT_logo.svg"
  "https://commons.wikimedia.org/wiki/Special:FilePath/ChatGPT_logo_Square.svg"
)
WIKI_PNG_WIDTHS=(512 256)

# Rounded-card parameters (override as env: CHATGPT_ICON_SIZE=..., CHATGPT_ICON_PADDING=..., CHATGPT_ICON_RADIUS=...)
CARD_SIZE="${CHATGPT_ICON_SIZE:-256}"
CARD_PAD="${CHATGPT_ICON_PADDING:-16}"
CARD_RADIUS="${CHATGPT_ICON_RADIUS:-36}"

# -------------------------------
# Dependencies
# -------------------------------
install_deps(){
  log "Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y curl wget xdg-utils desktop-file-utils librsvg2-tools ImageMagick
}

# -------------------------------
# Helpers
# -------------------------------
have(){ command -v "$1" >/dev/null 2>&1; }

download_file(){ # $1=url $2=dest
  local url="$1" dest="$2"
  if have curl; then sudo -u "$REAL_USER" curl -fsSL --retry 3 --retry-delay 1 -o "$dest" "$url" && return 0; fi
  if have wget; then sudo -u "$REAL_USER" wget -q -T 30 --tries=3 -O "$dest" "$url" && return 0; fi
  return 1
}

ensure_png_from_any(){ # $1=input(any), $2=output_png(256x256)
  local in="$1" out="$2"
  local mime
  mime="$(file -b --mime-type "$in" 2>/dev/null || echo '')"
  case "$mime" in
    image/png)   if have magick; then sudo -u "$REAL_USER" magick "$in" -resize 256x256 "$out"; else sudo -u "$REAL_USER" convert "$in" -resize 256x256 "$out"; fi ;;
    image/svg+xml) sudo -u "$REAL_USER" rsvg-convert -w 256 -h 256 "$in" -o "$out" ;;
    image/webp|image/x-icon|image/vnd.microsoft.icon|application/octet-stream|"")
      if have magick; then sudo -u "$REAL_USER" magick "$in" -resize 256x256 "$out"; else sudo -u "$REAL_USER" convert "$in" -resize 256x256 "$out"; fi ;;
    *)
      if have magick; then sudo -u "$REAL_USER" magick "$in" -resize 256x256 "$out"; else sudo -u "$REAL_USER" convert "$in" -resize 256x256 "$out"; fi ;;
  esac
}

# -------------------------------
# Fetch logo from Wikipedia + soften (rounded white card)
# -------------------------------
fetch_and_soften_icon(){
  sudo -u "$REAL_USER" mkdir -p "$APP_DIR"
  sudo -u "$REAL_USER" rm -f "$ICON_TMP" "$ICON_RAW" "$ICON_SVG" "$MASK" "$CARD" "$INNER"

  # 1) Try Commons-rendered PNG via ?width=
  if [[ -n "$WIKI_SVG_CANDIDATE" ]]; then
    for w in "${WIKI_PNG_WIDTHS[@]}"; do
      if download_file "${WIKI_SVG_CANDIDATE}?width=${w}" "$ICON_TMP" && [[ -s "$ICON_TMP" ]]; then
        ensure_png_from_any "$ICON_TMP" "$ICON_RAW" || true
        [[ -s "$ICON_RAW" ]] && break
      fi
    done
  fi
  if [[ ! -s "$ICON_RAW" ]]; then
    for u in "${WIKI_SVG_LIST[@]}"; do
      for w in "${WIKI_PNG_WIDTHS[@]}"; do
        sudo -u "$REAL_USER" rm -f "$ICON_TMP"
        if download_file "${u}?width=${w}" "$ICON_TMP" && [[ -s "$ICON_TMP" ]]; then
          ensure_png_from_any "$ICON_TMP" "$ICON_RAW" || true
          [[ -s "$ICON_RAW" ]] && break 2
        fi
      done
    done
  fi

  # 2) If PNG still missing, fetch raw SVG and rasterize
  if [[ ! -s "$ICON_RAW" ]]; then
    if [[ -n "$WIKI_SVG_CANDIDATE" ]]; then
      download_file "$WIKI_SVG_CANDIDATE" "$ICON_SVG" || true
    fi
    if [[ ! -s "$ICON_SVG" ]]; then
      for u in "${WIKI_SVG_LIST[@]}"; do
        sudo -u "$REAL_USER" rm -f "$ICON_SVG"
        if download_file "$u" "$ICON_SVG" && [[ -s "$ICON_SVG" ]]; then
          break
        fi
      done
    fi
    [[ -s "$ICON_SVG" ]] || die "Could not fetch ChatGPT logo from Wikipedia."
    sudo -u "$REAL_USER" rsvg-convert -w 512 -h 512 "$ICON_SVG" -o "$ICON_RAW" || die "Failed to render SVG to PNG."
  fi

  [[ -s "$ICON_RAW" ]] || die "Icon PNG not created."

  # 3) Build rounded white card with true rounded transparency (CopyOpacity)
  local inner=$(( CARD_SIZE - 2 * CARD_PAD ))
  (( inner > 0 )) || die "Padding too large for card size ${CARD_SIZE}."

  # inner logo, centered square
  if have magick; then
    sudo -u "$REAL_USER" magick "$ICON_RAW" -resize "${inner}x${inner}" -background none -gravity center -extent "${inner}x${inner}" "$INNER"
    # rounded alpha mask
    sudo -u "$REAL_USER" magick -size "${CARD_SIZE}x${CARD_SIZE}" xc:none \
      -fill white -draw "roundrectangle 0,0 $((CARD_SIZE-1)),$((CARD_SIZE-1)) ${CARD_RADIUS},${CARD_RADIUS}" \
      "$MASK"
    # white rounded card with transparent corners
    sudo -u "$REAL_USER" magick -size "${CARD_SIZE}x${CARD_SIZE}" xc:white "$MASK" -compose CopyOpacity -composite "$CARD"
    # composite inner onto card
    local ts="$(date +%s)"
    ICON_OUT="$APP_DIR/chatgpt-rounded-${CARD_SIZE}-p${CARD_PAD}-r${CARD_RADIUS}-${ts}.png"
    sudo -u "$REAL_USER" magick "$CARD" "$INNER" -gravity center -compose over -composite "$ICON_OUT"
  else
    sudo -u "$REAL_USER" convert "$ICON_RAW" -resize "${inner}x${inner}" -background none -gravity center -extent "${inner}x${inner}" "$INNER"
    sudo -u "$REAL_USER" convert -size "${CARD_SIZE}x${CARD_SIZE}" xc:none \
      -fill white -draw "roundrectangle 0,0 $((CARD_SIZE-1)),$((CARD_SIZE-1)) ${CARD_RADIUS},${CARD_RADIUS}" \
      "$MASK"
    sudo -u "$REAL_USER" convert -size "${CARD_SIZE}x${CARD_SIZE}" xc:white "$MASK" -compose CopyOpacity -composite "$CARD"
    local ts="$(date +%s)"
    ICON_OUT="$APP_DIR/chatgpt-rounded-${CARD_SIZE}-p${CARD_PAD}-r${CARD_RADIUS}-${ts}.png"
    sudo -u "$REAL_USER" convert "$CARD" "$INNER" -gravity center -compose over -composite "$ICON_OUT"
  fi

  sudo -u "$REAL_USER" rm -f "$ICON_TMP" "$MASK" "$CARD" "$INNER"
  [[ -s "$ICON_OUT" ]] || die "Final icon missing after softening step."
  log "Prepared rounded icon: $ICON_OUT"
}

# -------------------------------
# CLI launcher
# -------------------------------
write_cli_wrapper(){
  sudo -u "$REAL_USER" mkdir -p "$BIN_DIR" "$PROFILE_DIR"
  cat >"$CLI_WRAPPER" <<'EOSH'
#!/usr/bin/env bash
set -Eeuo pipefail

APP_URL="${CHATGPT_URL:-https://chatgpt.com/}"
APP_ID="chatgpt-ssb"
PROFILE_DIR="${HOME}/.local/share/chatgpt-chrome-profile"

detect_browser() {
  local c
  for c in google-chrome-stable google-chrome chromium chromium-browser brave-browser; do
    if command -v "$c" >/dev/null 2>&1; then echo "$c"; return 0; fi
  done
  return 1
}

BROWSER="$(detect_browser || true)"
if [[ -z "${BROWSER:-}" ]]; then
  echo "chatgpt: No supported browser (Chrome/Chromium/Brave) found." >&2
  exit 127
fi

force_x11="${CHATGPT_FORCE_X11:-1}"
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

  fetch_and_soften_icon

  # Use the new (cache-busted) file
  local icon_field="$ICON_OUT"

  cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=ChatGPT as a standalone web app
Exec=$CLI_WRAPPER
TryExec=$CLI_WRAPPER
StartupNotify=false
Terminal=false
Icon=$icon_field
Categories=Utility;AI;Network;GTK;
Keywords=chatgpt;ai;assistant;openai;gpt;
StartupWMClass=$APP_ID
DBusActivatable=false
X-GNOME-UsesNotifications=true
EOF
  sudo -u "$REAL_USER" chmod 0644 "$DESKTOP_FILE"
  log "Desktop file written (Icon=$icon_field)"
}

# -------------------------------
# Config / Clean / Install
# -------------------------------
configure(){
  if have update-desktop-database; then sudo -u "$REAL_USER" update-desktop-database "$LAUNCHER_DIR" || true; fi
  case ":$PATH:" in *":$HOME_DIR/.local/bin:"*) ;; *)
    log "Note: add '\$HOME_DIR/.local/bin' to PATH to use 'chatgpt'/'cgpt' from the terminal." ;;
  esac
  log "Done."
}

clean(){
  log "Removing launcher, icon and CLI..."
  sudo -u "$REAL_USER" rm -f "$DESKTOP_FILE"
  sudo -u "$REAL_USER" rm -rf "$APP_DIR"
  sudo -u "$REAL_USER" rm -f "$CLI_WRAPPER" "$CLI_ALIAS"
  sudo -u "$REAL_USER" rm -rf "$PROFILE_DIR"
}

do_install(){ write_cli_wrapper; write_desktop; }

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


