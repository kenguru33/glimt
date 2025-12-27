#!/usr/bin/env bash
# Glimt module: Install, configure and remove Snapper (Debian)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="snapper"
ACTION="${1:-all}"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

deb_guard() {
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || die "Debian-only module."
}

is_btrfs() {
  findmnt -n -o FSTYPE "$1" | grep -qx btrfs
}

has_config() {
  snapper list-configs 2>/dev/null | awk '{print $1}' | grep -qx "$1"
}

deps() {
  deb_guard
  log "Installing dependencies"
  sudo apt update
  sudo apt install -y btrfs-progs
}

install() {
  deb_guard

  if dpkg -s snapper &>/dev/null; then
    log "Snapper already installed"
    return
  fi

  log "Installing Snapper"
  sudo apt install -y snapper
}

config() {
  deb_guard

  if ! is_btrfs /; then
    log "Root filesystem is not Btrfs — skipping Snapper setup"
    return
  fi

  if ! has_config root; then
    log "Creating Snapper config for /"
    sudo snapper -c root create-config /
  else
    log "Snapper config for / already exists"
  fi

  if is_btrfs /home && ! has_config home; then
    log "Creating Snapper config for /home (Btrfs subvolume)"
    sudo snapper -c home create-config /home
  fi

  log "Enabling Snapper timers"
  sudo systemctl enable --now \
    snapper-timeline.timer \
    snapper-cleanup.timer
}

clean() {
  deb_guard

  for cfg in root home; do
    if has_config "$cfg"; then
      log "Removing Snapper config: $cfg"
      sudo snapper -c "$cfg" delete-config
    fi
  done

  log "Disabling Snapper timers"
  sudo systemctl disable --now \
    snapper-timeline.timer \
    snapper-cleanup.timer 2>/dev/null || true

  if dpkg -s snapper &>/dev/null; then
    log "Uninstalling Snapper"
    sudo apt remove -y snapper
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
