#!/usr/bin/env bash
# Glimt module: vscode (Flatpak)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ vscode module failed at line $LINENO" >&2' ERR

MODULE_NAME="vscode"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
LOCAL_BIN="$HOME_DIR/.local/bin"

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
deps() {
  require_user

  command -v flatpak >/dev/null || {
    echo "❌ flatpak not installed"
    exit 1
  }

  if ! flatpak remotes | awk '{print $1}' | grep -qx flathub; then
    log "➕ Adding Flathub remote"
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi

  mkdir -p "$LOCAL_BIN"
}

# --------------------------------------------------
install() {
  require_user

  log "📦 Installing VS Code (Flatpak)"

  if flatpak list | grep -q com.visualstudio.code; then
    log "✅ VS Code already installed"
  else
    flatpak install -y flathub com.visualstudio.code
  fi
}

# --------------------------------------------------
config() {
  require_user

  log "🔧 Installing 'code' terminal command"

  cat >"$LOCAL_BIN/code" <<'EOF'
#!/usr/bin/env bash
exec flatpak run com.visualstudio.code "$@"
EOF

  chmod +x "$LOCAL_BIN/code"

  # Refresh command cache for current shell if possible
  command -v hash >/dev/null && hash -r || true

  log "✅ 'code' command installed"
}

# --------------------------------------------------
clean() {
  require_user

  log "🧹 Removing VS Code"

  flatpak uninstall -y com.visualstudio.code || true
  rm -f "$LOCAL_BIN/code"

  log "✅ VS Code removed"
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
