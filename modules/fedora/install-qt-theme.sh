#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [qt-theme] Error on line $LINENO" >&2' ERR

MODULE_NAME="qt-theme"
ACTION="${1:-all}"

# ======================================================
# OS guard (Fedora / RHEL family)
# ======================================================
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS"
  exit 1
fi

[[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || {
  echo "❌ Fedora/RHEL-based systems only"
  exit 1
}

ENV_DIR="$HOME/.config/environment.d"
ENV_FILE="$ENV_DIR/qt.conf"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }

# ======================================================
# Helpers
# ======================================================
pkg_available() {
  dnf list --available "$1" >/dev/null 2>&1
}

# ======================================================
# Dependencies
# ======================================================
deps() {
  log "Installing Qt GNOME integration packages…"

  sudo dnf install -y \
    qt5-qtwayland \
    qt6-qtwayland

  if pkg_available adwaita-qt; then
    sudo dnf install -y adwaita-qt
    log "Installed adwaita-qt"
  else
    log "adwaita-qt not available – falling back to qtct"
    sudo dnf install -y qt5ct qt6ct
  fi
}

# ======================================================
# Install
# ======================================================
install() {
  deps
}

# ======================================================
# Config
# ======================================================
config() {
  log "Writing Qt environment configuration…"
  mkdir -p "$ENV_DIR"

  if rpm -q adwaita-qt >/dev/null 2>&1; then
    cat >"$ENV_FILE" <<EOF
QT_QPA_PLATFORMTHEME=gnome
QT_STYLE_OVERRIDE=adwaita-dark
EOF
    log "Configured Qt to use GNOME Adwaita Dark"
  else
    cat >"$ENV_FILE" <<EOF
QT_QPA_PLATFORMTHEME=qt6ct
QT_STYLE_OVERRIDE=adwaita-dark
EOF
    log "Configured Qt to use qtct fallback"
  fi

  log "Config written to $ENV_FILE"
  log "⚠️  Log out and back in to apply to GUI apps"
}

# ======================================================
# Clean
# ======================================================
clean() {
  log "Removing Qt theme configuration…"
  rm -f "$ENV_FILE"
  log "Qt environment config removed"
  log "⚠️  Log out and back in to fully reset GUI environment"
}

# ======================================================
# Dispatcher
# ======================================================
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
