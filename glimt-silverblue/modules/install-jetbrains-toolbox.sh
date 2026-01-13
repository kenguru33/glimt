#!/bin/bash
# Glimt module: jetbrains-toolbox
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ jetbrains-toolbox module failed." >&2' ERR

MODULE_NAME="jetbrains-toolbox"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

BASE_DIR="$HOME_DIR/.local/share/JetBrains/Toolbox"
TMP_DIR="/tmp/jetbrains-toolbox"
DESKTOP_FILE="$HOME_DIR/.local/share/applications/jetbrains-toolbox.desktop"
SYMLINK="$HOME_DIR/.local/bin/jetbrains-toolbox"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_user() {
  if [[ "$EUID" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    echo "❌ Do not run this module as root directly." >&2
    exit 1
  fi
}

# --------------------------------------------------
# OS check (Fedora/Silverblue)
# --------------------------------------------------
. /etc/os-release || exit 1

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* ]]; then
  log "❌ Fedora-based systems only"
  exit 1
fi

# --------------------------------------------------
deps() {
  log "📦 No additional dependencies required"
}

# --------------------------------------------------
install() {
  require_user

  if [[ -x "$BASE_DIR/bin/jetbrains-toolbox" ]]; then
    log "✅ JetBrains Toolbox already installed"
    return
  fi

  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  cd "$TMP_DIR"

  log "🌐 Fetching latest Toolbox URL"
  URL="$(curl -fsSL \
    "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" |
    jq -r '.TBA[0].downloads.linux.link')"

  [[ -n "$URL" && "$URL" != "null" ]] || {
    log "❌ Failed to resolve download URL"
    exit 1
  }

  ARCHIVE="${URL##*/}"

  log "⬇️  Downloading $ARCHIVE"
  curl -L "$URL" -o "$ARCHIVE"

  log "📦 Extracting"
  mkdir -p "$BASE_DIR"
  tar -xzf "$ARCHIVE" --strip-components=1 -C "$BASE_DIR"

  log "🚀 Launching Toolbox once for self-setup"
  nohup "$BASE_DIR/jetbrains-toolbox" >/dev/null 2>&1 &

  sleep 5
}

# --------------------------------------------------
config() {
  require_user

  BIN="$BASE_DIR/bin/jetbrains-toolbox"
  [[ -x "$BIN" ]] || BIN="$BASE_DIR/jetbrains-toolbox"

  [[ -x "$BIN" ]] || {
    log "❌ Toolbox binary not found"
    exit 1
  }

  mkdir -p "$(dirname "$DESKTOP_FILE")"

  ICON="$BASE_DIR/.install-icon.svg"
  [[ -f "$ICON" ]] || ICON="jetbrains-toolbox"

  cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=JetBrains Toolbox
Comment=Manage JetBrains IDEs
Exec=$BIN
Icon=$ICON
Terminal=false
Type=Application
Categories=Development;IDE;
StartupNotify=true
EOF

  chmod +x "$DESKTOP_FILE"
  update-desktop-database "$HOME_DIR/.local/share/applications" &>/dev/null || true

  mkdir -p "$HOME_DIR/.local/bin"
  ln -sf "$BIN" "$SYMLINK"

  log "✅ Desktop launcher and symlink created"
}

# --------------------------------------------------
clean() {
  require_user

  rm -rf "$BASE_DIR"
  rm -f "$DESKTOP_FILE"
  rm -f "$SYMLINK"
  rm -rf "$TMP_DIR"

  update-desktop-database "$HOME_DIR/.local/share/applications" &>/dev/null || true

  log "🧹 JetBrains Toolbox removed"
}

# --------------------------------------------------
case "$ACTION" in
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
all)
  deps
  install
  config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac

exit 0
