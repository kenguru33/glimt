#!/usr/bin/env bash
# modules/debian/install-navicat.sh
# Glimt module: Install Navicat Premium (AppImage) for the current user on Debian.
# Pattern: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="navicat"
ACTION="${1:-all}"

# ---- Config ----
: "${APPDIR:=$HOME/.local/opt/navicat}"
: "${BINDIR:=$HOME/.local/bin}"
: "${DESKTOP_DIR:=$HOME/.local/share/applications}"
: "${CACHE:=${TMPDIR:-/tmp}/.navicat-dl}"
: "${NAVICAT_URL:=https://dn.navicat.com/download/navicat17-premium-en-x86_64.AppImage}"

mkdir -p "$APPDIR" "$BINDIR" "$DESKTOP_DIR" "$CACHE"

# ---- Helpers ----
log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }   # << write logs to stderr
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

deb_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || die "Debian-only module."
  else
    die "Cannot detect OS."
  fi
}

install_deps() {
  log "Installing dependencies (sudo): libfuse2, ca-certificates, curl, desktop-file-utils"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends libfuse2 ca-certificates curl desktop-file-utils
}

download_navicat() {
  local url filename
  url="$NAVICAT_URL"
  filename="${url##*/}"
  log "Downloading: $url"
  curl -fL --retry 3 -o "$CACHE/$filename" "$url" || die "Download failed."
  printf '%s\n' "$CACHE/$filename"
}

install_navicat() {
  local appimage src dst
  appimage="$(download_navicat)"
  src="$appimage"
  dst="$APPDIR/navicat.AppImage"

  install -m 0755 "$src" "$dst"
  ln -sf "$dst" "$BINDIR/navicat"
  log "Installed to $dst and symlinked as $BINDIR/navicat"

  # Try to extract an icon
  if "$dst" --appimage-extract >/dev/null 2>&1; then
    local icon_path
    icon_path="$(find squashfs-root -type f -name '*.png' -printf '%s\t%p\n' 2>/dev/null | sort -nr | head -n1 | cut -f2- || true)"
    if [[ -n "${icon_path:-}" ]]; then
      install -m 0644 "$icon_path" "$APPDIR/navicat.png"
      log "Icon extracted to $APPDIR/navicat.png"
    fi
    rm -rf squashfs-root
  else
    log "Icon extraction skipped (AppImage --appimage-extract unavailable)."
  fi
}

write_desktop_file() {
  local desktop_file="$DESKTOP_DIR/navicat.desktop"
  local icon="$APPDIR/navicat.png"
  [[ -f "$icon" ]] || icon="navicat"

  cat > "$desktop_file" <<EOF
[Desktop Entry]
Name=Navicat Premium
Comment=Database administration & development
Exec=$APPDIR/navicat.AppImage %U
Icon=$icon
Terminal=false
Type=Application
Categories=Development;Database;
MimeType=application/x-sqlite3;application/sql;
StartupNotify=true
EOF

  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
  log "Desktop entry written: $desktop_file"
}

configure_navicat() {
  true
}

clean_navicat() {
  log "Removing files"
  rm -f "$BINDIR/navicat"
  rm -f "$DESKTOP_DIR/navicat.desktop"
  rm -rf "$APPDIR"
  log "Clean complete."
}

# ---- Entry point ----
deb_guard

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    install_navicat
    ;;
  config)
    configure_navicat
    write_desktop_file
    ;;
  clean)
    clean_navicat
    ;;
  all)
    install_deps
    install_navicat
    configure_navicat
    write_desktop_file
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

log "Done: $ACTION"
