#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="nvidia"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

RPMFUSION_FREE="https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
RPMFUSION_NONFREE="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"

KERNEL_ARGS="nvidia-drm.modeset=1 nvidia-drm.fbdev=1"

# === OS Check =============================================================
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  die "Cannot detect OS. /etc/os-release missing."
fi

if [[ "$ID" != "fedora" ]]; then
  die "This module supports Fedora only."
fi

# === Actions ==============================================================

deps() {
  log "Enabling RPM Fusion free and nonfree repositories…"

  if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
    sudo dnf install -y "$RPMFUSION_FREE"
  else
    log "RPM Fusion free already enabled."
  fi

  if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
    sudo dnf install -y "$RPMFUSION_NONFREE"
  else
    log "RPM Fusion nonfree already enabled."
  fi
}

install() {
  log "Installing NVIDIA driver (akmod-nvidia)…"
  sudo dnf install -y akmod-nvidia nvidia-settings
  log "Driver packages installed. Kernel module will be built on next boot."
}

config() {
  log "Configuring kernel parameters for Wayland (${KERNEL_ARGS})…"

  local current_args
  current_args="$(sudo grubby --info=DEFAULT | grep '^args=' | sed 's/^args=//' | tr -d '"')"

  local needs_update=false
  for arg in $KERNEL_ARGS; do
    if [[ "$current_args" != *"$arg"* ]]; then
      needs_update=true
      break
    fi
  done

  if [[ "$needs_update" == true ]]; then
    # shellcheck disable=SC2086
    sudo grubby --update-kernel=ALL --args="$KERNEL_ARGS"
    log "Kernel parameters updated. A reboot is required."
  else
    log "Kernel parameters already set."
  fi
}

clean() {
  log "Removing NVIDIA driver and kernel parameters…"

  sudo dnf remove -y akmod-nvidia nvidia-settings kmod-nvidia \
    xorg-x11-drv-nvidia xorg-x11-drv-nvidia-cuda \
    xorg-x11-drv-nvidia-libs xorg-x11-drv-nvidia-libs.i686 || true

  log "Removing kernel parameters…"
  # shellcheck disable=SC2086
  sudo grubby --update-kernel=ALL --remove-args="$KERNEL_ARGS" || true

  log "NVIDIA driver removed. A reboot is required."
}

all() {
  deps
  install
  config
  log "Done. Reboot to activate the NVIDIA driver."
}

case "$ACTION" in
deps)    deps ;;
install) install ;;
config)  config ;;
clean)   clean ;;
all)     all ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 2
  ;;
esac
