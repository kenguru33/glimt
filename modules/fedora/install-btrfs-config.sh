#!/usr/bin/env bash
# Glimt module: Install, configure and remove Snapper (Fedora, Btrfs-root only)
# Timeline enabled for /, dnf pre/post snapshots enabled
# COW disabled for VM disk images
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="snapper"
ACTION="${1:-all}"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

# ---------------------------------------------------------
# Guards & helpers
# ---------------------------------------------------------
fedora_guard() {
  . /etc/os-release
  [[ "${ID:-}" == "fedora" ]] || die "Fedora-only module."
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

disable_cow_dir() {
  local dir="$1"

  if [[ ! -d "$dir" ]]; then
    return
  fi

  if lsattr -d "$dir" 2>/dev/null | grep -q 'C'; then
    log "COW already disabled: $dir"
    return
  fi

  log "Disabling COW on $dir"
  sudo chattr +C "$dir" || true
}

# ---------------------------------------------------------
# deps
# ---------------------------------------------------------
deps() {
  fedora_guard
  log "Installing Btrfs and Snapper dependencies"
  sudo dnf install -y \
    btrfs-progs \
    btrfs-assistant \
    snapper-dnf
}

# ---------------------------------------------------------
# install
# ---------------------------------------------------------
install() {
  fedora_guard

  if ! is_btrfs /; then
    log "Root filesystem is not Btrfs — Snapper will not be installed"
    return
  fi

  if rpm -q snapper &>/dev/null; then
    log "Snapper already installed"
    return
  fi

  log "Installing Snapper (Btrfs root detected)"
  sudo dnf install -y snapper
}

# ---------------------------------------------------------
# config
# ---------------------------------------------------------
config() {
  fedora_guard

  if ! is_btrfs /; then
    log "Root filesystem is not Btrfs — skipping Snapper configuration"
    return
  fi

  if ! rpm -q snapper &>/dev/null; then
    log "Snapper not installed — skipping configuration"
    return
  fi

  # -----------------------------------------------------
  # Root Snapper config (ONLY root)
  # -----------------------------------------------------
  if ! has_config root; then
    log "Creating Snapper config for /"
    sudo snapper -c root create-config /
  else
    log "Snapper config for / already exists"
  fi

  ROOT_CFG="/etc/snapper/configs/root"

  log "Configuring Snapper (root timeline only)"

  ensure_kv "$ROOT_CFG" TIMELINE_CREATE "yes"
  ensure_kv "$ROOT_CFG" TIMELINE_CLEANUP "yes"
  ensure_kv "$ROOT_CFG" NUMBER_CLEANUP "yes"

  # VM-safe limits
  ensure_kv "$ROOT_CFG" TIMELINE_LIMIT_HOURLY "6"
  ensure_kv "$ROOT_CFG" TIMELINE_LIMIT_DAILY "7"
  ensure_kv "$ROOT_CFG" TIMELINE_LIMIT_WEEKLY "0"
  ensure_kv "$ROOT_CFG" TIMELINE_LIMIT_MONTHLY "0"
  ensure_kv "$ROOT_CFG" TIMELINE_LIMIT_YEARLY "0"

  # Exclude VM disk images from snapshots
  ensure_kv "$ROOT_CFG" EXCLUDE "home/*/.local/share/gnome-boxes/images"

  log "Enabling Snapper timeline + cleanup timers"
  sudo systemctl enable --now \
    snapper-timeline.timer \
    snapper-cleanup.timer

  # -----------------------------------------------------
  # Disable COW on VM images (performance + safety)
  # -----------------------------------------------------
  disable_cow_dir "/home/*/.local/share/gnome-boxes/images"
  disable_cow_dir "/home/*/.VirtualBox"

  log "Snapper configured: root timeline, dnf snapshots, COW disabled for VM images"
}

# ---------------------------------------------------------
# clean
# ---------------------------------------------------------
clean() {
  fedora_guard

  if rpm -q snapper &>/dev/null; then
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

    log "Uninstalling Snapper"
    sudo dnf remove -y snapper snapper-dnf
  else
    log "Snapper not installed — nothing to clean"
  fi
}

# ---------------------------------------------------------
# entrypoint
# ---------------------------------------------------------
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
