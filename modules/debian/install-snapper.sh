#!/usr/bin/env bash
# Glimt module: Install, configure and remove Snapper (Debian, VM-safe)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="snapper"
ACTION="${1:-all}"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

debian_guard() {
  . /etc/os-release
  [[ "${ID:-}" == "debian" || "${ID_LIKE:-}" == *debian* ]] ||
    die "Debian-only module."
}

is_btrfs() {
  findmnt -n -o FSTYPE "$1" 2>/dev/null | grep -qx btrfs
}

has_config() {
  snapper list-configs 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$1"
}

ensure_kv() {
  local file="$1" key="$2" value="$3"
  if grep -q "^${key}=" "$file"; then
    sudo sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$file"
  else
    echo "${key}=\"${value}\"" | sudo tee -a "$file" >/dev/null
  fi
}

deps() {
  debian_guard
  log "Installing dependencies"
  sudo apt update
  sudo apt install -y btrfs-progs
}

install() {
  debian_guard

  if dpkg -s snapper &>/dev/null; then
    log "Snapper already installed"
    return
  fi

  log "Installing Snapper"
  sudo apt install -y snapper
}

config() {
  debian_guard

  if ! is_btrfs /; then
    log "Root filesystem is not Btrfs — skipping Snapper setup"
    return
  fi

  # ---- Root config only ----
  if ! has_config root; then
    log "Creating Snapper config for /"
    sudo snapper -c root create-config /
  else
    log "Snapper config for / already exists"
  fi

  ROOT_CFG="/etc/snapper/configs/root"

  log "Configuring Snapper (VM-safe defaults)"
  ensure_kv "$ROOT_CFG" TIMELINE_CREATE "no"
  ensure_kv "$ROOT_CFG" NUMBER_CLEANUP "yes"
  ensure_kv "$ROOT_CFG" TIMELINE_CLEANUP "yes"

  # Exclude GNOME Boxes VM disks
  ensure_kv "$ROOT_CFG" EXCLUDE "home/*/.local/share/gnome-boxes/images"

  log "Enabling Snapper cleanup timer only"
  sudo systemctl enable --now snapper-cleanup.timer
  sudo systemctl disable --now snapper-timeline.timer 2>/dev/null || true

  log "Snapper configured (no timelines, safe for VMs)"
}

clean() {
  debian_guard

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
