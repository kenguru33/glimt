#!/usr/bin/env bash
# modules/install-ytmusic-pwa.sh
# Glimt: YouTube Music PWA (Chrome/Chromium/Brave) – Debian only
# Actions: all | deps | install | config | clean
set -Eeuo pipefail
trap 'echo "ERROR at line $LINENO: $BASH_COMMAND" >&2' ERR

MODULE_NAME="ytmusic-pwa"
ACTION="${1:-all}"

log(){ printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

# ---- Debian-only guard ----
if [[ -r /etc/os-release ]]; then . /etc/os-release
else die "Kan ikke detektere OS."; fi
[[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *"debian"* ]] || die "Kun Debian/Debian-derivater støttes."

# ---- App metadata ----
APP_NAME="YouTube Music"
APP_URL="https://music.youtube.com"
APP_ID="ytmusic-ssb"
LAUNCHER_DIR="$HOME/.local/share/applications"
APP_DIR="$HOME/.local/share/ytmusic-pwa"
PROFILE_DIR="$HOME/.local/share/ytmusic-chrome-profile"
DESKTOP_FILE="$LAUNCHER_DIR/${APP_ID}.desktop"
ICON_SVG="$APP_DIR/icon.svg"
ICON_PNG="$APP_DIR/icon.png"
BIN_DIR="$HOME/.local/bin"
CLI_WRAPPER="$BIN_DIR/ytmusic"
CLI_ALIAS="$BIN_DIR/ytm"

ICON_SRC_SVG="https://upload.wikimedia.org/wikipedia/commons/6/6a/Youtube_Music_icon.svg"

# ---- Browser detection ----
detect_browser(){
  local c
  for c in google-chrome-stable google-chrome chromium chromium-browser brave-browser; do
    if command -v "$c" >/dev/null 2>&1; then
      BROWSER="$(command -v "$c")"
      break
    fi
  done
  [[ -n "${BROWSER:-}" ]] || die "Ingen støttet nettleser funnet (Chrome/Chromium/Brave)."
}

# ---- Flags (X11 som default på Wayland) ----
compose_flags(){
  local force_x11="${YTMUSIC_FORCE_X11:-1}"
  BFLAGS=(--no-first-run --no-default-browser-check --disable-sync --disable-extensions
          --user-data-dir="$PROFILE_DIR" --class="$APP_ID" --app="$APP_URL")
  if [[ "${XDG_SESSION_TYPE:-}" == "wayland" && "$force_x11" == "1" ]]; then
    ENV_PREFIX=(env GDK_BACKEND=x11 XDG_SESSION_TYPE=x11)
    BFLAGS+=(--ozone-platform=x11)
  else
    BFLAGS+=(--enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform=wayland)
  fi
}

# ---- Deps (Debian) ----
install_deps(){
  log "Installerer avhengigheter…"
  sudo apt update
  sudo apt install -y wget xdg-utils desktop-file-utils librsvg2-bin
}

# ---- Ikon ----
ensure_icon(){
  mkdir -p "$APP_DIR"
  if [[ ! -s "$ICON_SVG" ]]; then
    log "Laster ned ikon…"
    wget -qO "$ICON_SVG" "$ICON_SRC_SVG"
  fi
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 256 -h 256 "$ICON_SVG" -o "$ICON_PNG" || true
  fi
}

# ---- .desktop ----
write_desktop(){
  mkdir -p "$LAUNCHER_DIR" "$PROFILE_DIR"
  detect_browser
  compose_flags
  ensure_icon

  local icon_path="$ICON_PNG"; [[ -s "$icon_path" ]] || icon_path="$ICON_SVG"

  log "Oppretter launcher: $DESKTOP_FILE"
  cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
Comment=Play music from YouTube Music
Exec=${ENV_PREFIX[*]} "$BROWSER" ${BFLAGS[*]}
StartupNotify=false
Terminal=false
Icon=$icon_path
Categories=Audio;Music;Player;GTK;
Keywords=music;audio;youtube;yt;stream;
StartupWMClass=$APP_ID
TryExec=$BROWSER
X-GNOME-UsesNotifications=true
EOF
  chmod 0644 "$DESKTOP_FILE"
}

# ---- CLI launcher (~/.local/bin/ytmusic + ytm) ----
write_cli_wrapper(){
  mkdir -p "$BIN_DIR" "$PROFILE_DIR"
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
  chmod 0755 "$CLI_WRAPPER"
  ln -sf "$CLI_WRAPPER" "$CLI_ALIAS"
  log "CLI: $(basename "$CLI_WRAPPER") (alias: $(basename "$CLI_ALIAS"))"
}

# ---- Config ----
configure(){
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$LAUNCHER_DIR" || true
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *)
    log "Tips: legg til '\$HOME/.local/bin' i PATH for å bruke 'ytmusic'/'ytm'." ;;
  esac
  log "Ferdig."
}

# ---- Clean ----
clean(){
  log "Fjerner launcher, ikon og CLI…"
  rm -f "$DESKTOP_FILE"
  rm -rf "$APP_DIR"
  rm -f "$CLI_WRAPPER" "$CLI_ALIAS"
  # Slett profil (kommenter ut for å beholde innlogging/cookies)
  rm -rf "$PROFILE_DIR"
}

# ---- Install ----
do_install(){ write_desktop; write_cli_wrapper; }

case "$ACTION" in
  deps)    install_deps ;;
  install) do_install ;;
  config)  configure ;;
  clean)   clean ;;
  all)     install_deps; do_install; configure ;;
  *)       die "Ukjent action: $ACTION (bruk all|deps|install|config|clean)" ;;
esac
