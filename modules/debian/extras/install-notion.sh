#!/usr/bin/env bash
# Glimt: Notion (Chrome app-mode, isolated profile, X11-forced on Wayland)
# Actions: all | install | clean | config
# Debian-only, user-scope, no sudo.
set -Eeuo pipefail
trap 'echo "ERROR at line $LINENO: $BASH_COMMAND" >&2' ERR

BIN_DIR="$HOME/.local/bin"
CLI_LAUNCHER="$BIN_DIR/notion"

MODULE_NAME="notion-chrome"
ACTION="${1:-all}"
log(){ printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

# Debian guard
if [[ -r /etc/os-release ]]; then . /etc/os-release
else die "Cannot detect OS."; fi
[[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *"debian"* ]] || die "Debian-only module."

APP_NAME="Notion"
APP_URL="https://www.notion.so"
WMCLASS="notion-ssb"                                  # must match desktop file basename on X11
PROFILE_DIR="$HOME/.local/share/notion-chrome-profile"
LAUNCHER_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons"
ICON_FILE="$ICON_DIR/notion.png"
DESKTOP_FILE="$LAUNCHER_DIR/${WMCLASS}.desktop"

detect_chrome() {
  command -v google-chrome >/dev/null 2>&1 && { command -v google-chrome; return; }
  command -v google-chrome-stable >/dev/null 2>&1 && { command -v google-chrome-stable; return; }
  return 1
}

# Force X11 under Wayland so GNOME uses WM_CLASS (reliable icon mapping)
effective_flags() {
  if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
    printf "%s" "--ozone-platform=x11"
  else
    printf "%s" ""
  fi
}

fetch_icon() {
  mkdir -p "$ICON_DIR"
  local tmp="/tmp/notion-icon.$$"; rm -f "$tmp" || true
  for url in \
    "https://www.notion.so/front-static/favicon/notion-app-icon-256.png" \
    "https://www.notion.so/front-static/favicon/notion-icon-192.png" \
    "https://www.notion.so/images/favicon.ico"
  do
    if wget -q -O "$tmp" "$url"; then break; fi
  done
  if [[ -s "$tmp" ]]; then mv -f "$tmp" "$ICON_FILE"; log "Icon saved: $ICON_FILE"
  else rm -f "$tmp" || true; log "Could not fetch icon (best-effort)."; fi
}

remove_old_launchers() {
  log "Cleaning old launchers…"
  rm -f "$LAUNCHER_DIR/Notion.desktop" 2>/dev/null || true
  find "$LAUNCHER_DIR" -maxdepth 1 -type f -name "*notion*.desktop" ! -name "$(basename "$DESKTOP_FILE")" -print0 \
    | xargs -0r rm -f
  update-desktop-database "$LAUNCHER_DIR" >/dev/null 2>&1 || true
}

write_cli_launcher() {
  local chrome_bin="$1" flags; flags="$(effective_flags)"
  mkdir -p "$BIN_DIR"

  cat > "$CLI_LAUNCHER" <<EOF
#!/usr/bin/env bash
exec $chrome_bin --class=$WMCLASS --name=$WMCLASS --user-data-dir="$PROFILE_DIR" --app=$APP_URL $flags "\$@"
EOF

  chmod +x "$CLI_LAUNCHER"
  log "CLI launcher written: $CLI_LAUNCHER (run 'notion' from terminal)"
}


write_desktop_file() {
  local chrome_bin="$1" flags; flags="$(effective_flags)"
  mkdir -p "$LAUNCHER_DIR" "$PROFILE_DIR"

  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=$APP_NAME
Comment=Open Notion in a chromeless Chrome window
Exec=$chrome_bin --class=$WMCLASS --name=$WMCLASS --user-data-dir=$PROFILE_DIR --app=$APP_URL $flags
TryExec=$chrome_bin
Terminal=false
Type=Application
Icon=$ICON_FILE
Categories=Office;Productivity;
StartupNotify=false
# X11: GNOME matches by WM_CLASS (we set it via --class/--name)
StartupWMClass=$WMCLASS
EOF

  command -v desktop-file-validate >/dev/null 2>&1 && desktop-file-validate "$DESKTOP_FILE" || true
  update-desktop-database "$LAUNCHER_DIR" >/dev/null 2>&1 || true
  log "Launcher written: $DESKTOP_FILE"
}

do_install() {
  local chrome_bin; chrome_bin="$(detect_chrome)" || die "Google Chrome not found. Install Chrome first."
  remove_old_launchers
  fetch_icon
  write_desktop_file "$chrome_bin"
  write_cli_launcher "$chrome_bin"
  log "Installed. Launch “$APP_NAME” from the app grid or run 'notion' in a terminal."
  log "Note: On Wayland this window runs under XWayland to ensure correct icon."
}


do_clean() {
  log "Removing Notion launcher, icon, profile, and CLI wrapper…"
  rm -f "$DESKTOP_FILE" "$ICON_FILE" "$CLI_LAUNCHER"
  [[ -d "$PROFILE_DIR" ]] && rm -rf "$PROFILE_DIR"
  update-desktop-database "$LAUNCHER_DIR" >/dev/null 2>&1 || true
  log "Clean complete."
}

do_config(){ log "No extra config."; }

case "$ACTION" in
  install) do_install ;;
  clean)   do_clean ;;
  config)  do_config ;;
  all)     do_install; do_config ;;
  *)       die "Usage: $0 [all|install|clean|config]" ;;
esac
