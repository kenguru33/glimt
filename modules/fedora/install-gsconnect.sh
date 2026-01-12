#!/usr/bin/env bash
# Glimt module: gsconnect
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ gsconnect module failed at line $LINENO" >&2' ERR

MODULE_NAME="gsconnect"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_sudo() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "❌ [$MODULE_NAME] Must be run with sudo" >&2
    exit 1
  fi
}

# --------------------------------------------------
# deps
# --------------------------------------------------
deps() {
  log "No additional dependencies required"
}

# --------------------------------------------------
# install
# --------------------------------------------------
install() {
  require_sudo

  if rpm -q gnome-shell-extension-gsconnect &>/dev/null; then
    log "GSConnect already installed"
  else
    log "Installing GSConnect via dnf"
    dnf install -y gnome-shell-extension-gsconnect
  fi
}

# --------------------------------------------------
# config
# --------------------------------------------------
config() {
  log "Enabling GSConnect extension for user: $REAL_USER"

  sudo -u "$REAL_USER" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$REAL_USER")/bus" \
    gnome-extensions enable gsconnect@andyholmes.github.io || {
    log "Extension will be enabled after next login"
  }
}

# --------------------------------------------------
# clean
# --------------------------------------------------
clean() {
  require_sudo

  log "Removing GSConnect via dnf"
  dnf remove -y gnome-shell-extension-gsconnect || true
}

# --------------------------------------------------
# entrypoint
# --------------------------------------------------
case "$ACTION" in
all)
  deps
  install
  config
  ;;
deps)
  deps
  ;;
install)
  install
  ;;
config)
  config
  ;;
clean)
  clean
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac
