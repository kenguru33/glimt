#!/usr/bin/env bash
# Glimt module: Enable Snapper integration with DNF (Fedora)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="snapper-dnf"
ACTION="${1:-all}"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

fedora_guard() {
  . /etc/os-release
  [[ "$ID" == "fedora" ]] || die "Fedora-only module."
}

snapper_ready() {
  command -v snapper >/dev/null || return 1
  snapper list-configs 2>/dev/null | grep -q '^root'
}

deps() {
  fedora_guard
  log "No extra dependencies required"
}

install() {
  fedora_guard

  if rpm -q dnf-plugin-snapper &>/dev/null; then
    log "dnf-plugin-snapper already installed"
    return
  fi

  log "Installing dnf-plugin-snapper"
  sudo dnf install -y dnf-plugin-snapper
}

config() {
  fedora_guard

  if ! snapper_ready; then
    die "Snapper root config not found. Install/configure Snapper first."
  fi

  log "DNF Snapper plugin enabled automatically when installed"
  log "Snapshots will be created before and after DNF transactions"
}

clean() {
  fedora_guard

  if rpm -q dnf-plugin-snapper &>/dev/null; then
    log "Removing dnf-plugin-snapper"
    sudo dnf remove -y dnf-plugin-snapper
  else
    log "dnf-plugin-snapper not installed"
  fi
}

case "$ACTION" in
all)
  deps
  install
  config
  ;;
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  die "Unknown action: $ACTION (use: all | deps | install | config | clean)"
  ;;
esac
