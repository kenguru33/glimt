#!/usr/bin/env bash
# Glimt: Notion (Chrome app-mode, isolated profile, X11-forced on Wayland)
# Actions: all | deps | install | config | clean
# Fedora-only. deps uses sudo dnf; everything else is user-scope (run as $REAL_USER).
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="notion-chrome"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

# ---- Fedora-only guard ----
fedora_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "${ID:-}" == "fedora" || "${ID_LIKE:-}" == *"fedora"* || "${ID:-}" == "rhel" ]] || die "Fedora/RHEL-only module."
  else
    die "Cannot detect OS."
  fi
}

BIN_DIR="$HOME_DIR/.local/bin"
CLI_LAUNCHER="$BIN_DIR/notion"

APP_NAME="Notion"
APP_URL="https://www.notion.so"
WMCLASS="notion-ssb"                                  # must match desktop file basename on X11
PROFILE_DIR="$HOME_DIR/.local/share/notion-chrome-profile"
LAUNCHER_DIR="$HOME_DIR/.local/share/applications"
ICON_DIR="$HOME_DIR/.local/share/icons"
ICON_FILE="$ICON_DIR/notion.png"
DESKTOP_FILE="$LAUNCHER_DIR/${WMCLASS}.desktop"
# Launchers written by earlier versions of this module — the only ones we
# remove besides $DESKTOP_FILE. Other *notion*.desktop files (Chrome PWAs,
# Flatpak/RPM Notion clients, the user's own) are left alone.
LEGACY_LAUNCHERS=(Notion.desktop)

# --- Deps ---
install_deps(){
  log "Installing dependencies..."
  dnf_ensure curl wget xdg-utils desktop-file-utils
}

detect_chrome() {
  command -v google-chrome >/dev/null 2>&1 && { command -v google-chrome; return; }
  command -v google-chrome-stable >/dev/null 2>&1 && { command -v google-chrome-stable; return; }
  command -v chromium >/dev/null 2>&1 && { command -v chromium; return; }
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
  sudo -u "$REAL_USER" mkdir -p "$ICON_DIR"
  local tmp
  tmp="$(run_as_user mktemp "${TMPDIR:-/tmp}/notion-icon.XXXXXX")"
  for url in \
    "https://www.notion.so/front-static/favicon/notion-app-icon-256.png" \
    "https://www.notion.so/front-static/favicon/notion-icon-192.png" \
    "https://www.notion.so/images/favicon.ico"
  do
    if sudo -u "$REAL_USER" curl -fsSL -o "$tmp" "$url" || sudo -u "$REAL_USER" wget -q -O "$tmp" "$url"; then break; fi
  done
  if [[ -s "$tmp" ]]; then
    sudo -u "$REAL_USER" mv -f "$tmp" "$ICON_FILE"
    log "Icon saved: $ICON_FILE"
  else
    sudo -u "$REAL_USER" rm -f "$tmp" || true
    log "Could not fetch icon (best-effort)."
  fi
}

remove_old_launchers() {
  log "Cleaning old launchers…"
  local f
  for f in "${LEGACY_LAUNCHERS[@]}"; do
    [[ "$f" == "$(basename "$DESKTOP_FILE")" ]] && continue
    if [[ -f "$LAUNCHER_DIR/$f" ]]; then
      run_as_user rm -f "$LAUNCHER_DIR/$f"
    fi
  done
  sudo -u "$REAL_USER" update-desktop-database "$LAUNCHER_DIR" >/dev/null 2>&1 || true
}

write_cli_launcher() {
  local chrome_bin="$1" flags; flags="$(effective_flags)"
  sudo -u "$REAL_USER" mkdir -p "$BIN_DIR"

  run_as_user tee "$CLI_LAUNCHER" >/dev/null <<EOF
#!/usr/bin/env bash
exec $chrome_bin --class=$WMCLASS --name=$WMCLASS --user-data-dir="$PROFILE_DIR" --app=$APP_URL $flags "\$@"
EOF

  run_as_user chmod +x "$CLI_LAUNCHER"
  log "CLI launcher written: $CLI_LAUNCHER (run 'notion' from terminal)"
}


write_desktop_file() {
  local chrome_bin="$1" flags; flags="$(effective_flags)"
  sudo -u "$REAL_USER" mkdir -p "$LAUNCHER_DIR" "$PROFILE_DIR"

  run_as_user tee "$DESKTOP_FILE" >/dev/null <<EOF
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

  run_as_user chmod 0644 "$DESKTOP_FILE"
  command -v desktop-file-validate >/dev/null 2>&1 && sudo -u "$REAL_USER" desktop-file-validate "$DESKTOP_FILE" || true
  sudo -u "$REAL_USER" update-desktop-database "$LAUNCHER_DIR" >/dev/null 2>&1 || true
  log "Launcher written: $DESKTOP_FILE"
}

do_install() {
  local chrome_bin; chrome_bin="$(detect_chrome)" || die "Google Chrome/Chromium not found. Install Chrome/Chromium first."
  remove_old_launchers
  fetch_icon
  write_desktop_file "$chrome_bin"
  write_cli_launcher "$chrome_bin"
  log "Installed. Launch $APP_NAME from the app grid or run 'notion' in a terminal."
  log "Note: On Wayland this window runs under XWayland to ensure correct icon."
}

do_clean() {
  log "Removing Notion launcher, icon, profile, and CLI wrapper…"
  sudo -u "$REAL_USER" rm -f "$DESKTOP_FILE" "$ICON_FILE" "$CLI_LAUNCHER"
  [[ -d "$PROFILE_DIR" ]] && sudo -u "$REAL_USER" rm -rf "$PROFILE_DIR"
  sudo -u "$REAL_USER" update-desktop-database "$LAUNCHER_DIR" >/dev/null 2>&1 || true
  log "Clean complete."
}

do_config(){ log "No extra config."; }

fedora_guard

case "$ACTION" in
  deps)    install_deps ;;
  install) do_install ;;
  clean)   do_clean ;;
  config)  do_config ;;
  all)     install_deps; do_install; do_config ;;
  *)       die "Usage: $0 [all|deps|install|clean|config]" ;;
esac

