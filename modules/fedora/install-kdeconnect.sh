#!/usr/bin/env bash
# Glimt module: kdeconnect (GSConnect backend)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ kdeconnect module failed." >&2' ERR

MODULE_NAME="kdeconnect"
ACTION="${1:-all}"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_sudo() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "❌ This module requires sudo." >&2
    exit 1
  fi
}

is_installed() {
  rpm -q kdeconnect >/dev/null 2>&1
}

deps() {
  require_sudo
  log "No additional dependencies required"
}

install() {
  require_sudo

  if is_installed; then
    log "kdeconnect already installed — skipping"
    return 0
  fi

  log "Installing kdeconnect"
  dnf install -y kde-connect
}

config() {
  log "No configuration required"
}

clean() {
  require_sudo

  if ! is_installed; then
    log "kdeconnect not installed — nothing to remove"
    return 0
  fi

  log "Removing kdeconnect"
  dnf remove -y kdeconnect
}

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
    echo "Usage: $0 {all|deps|install|config|clean}" >&2
    exit 1
    ;;
esac
