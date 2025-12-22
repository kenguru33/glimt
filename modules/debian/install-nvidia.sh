#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ NVIDIA CUDA installation failed." >&2' ERR

ACTION="${1:-all}"
shift || true

HEADLESS=false
FORCE_DKMS=false
PIN_DRIVER=false

for arg in "$@"; do
  case "$arg" in
  --headless | --server) HEADLESS=true ;;
  --force-dkms) FORCE_DKMS=true ;;
  --pin-driver) PIN_DRIVER=true ;;
  esac
done

log() { echo -e "➡️  $*"; }
warn() { echo -e "⚠️  $*" >&2; }
die() {
  echo -e "❌ $*" >&2
  exit 1
}

# ==========================================================
# GPU check
# ==========================================================
if ! lspci | grep -qi nvidia; then
  warn "No NVIDIA GPU detected — exiting."
  exit 0
fi

# ==========================================================
# OS detection
# ==========================================================
. /etc/os-release || die "Cannot detect OS"

case "$VERSION_CODENAME" in
bookworm) CUDA_DISTRO="debian12" ;;
trixie) CUDA_DISTRO="debian13" ;;
*) die "Unsupported Debian version: $VERSION_CODENAME" ;;
esac

ARCH="x86_64"
CUDA_BASE="https://developer.download.nvidia.com/compute/cuda/repos/${CUDA_DISTRO}/${ARCH}"

# ==========================================================
# deps
# ==========================================================
deps() {
  log "Installing base dependencies…"
  apt update
  apt install -y \
    wget gnupg build-essential dkms \
    linux-image-amd64 linux-headers-amd64 \
    mokutil openssl
}

# ==========================================================
# CUDA repo + keyring (MANDATORY)
# ==========================================================
preconfig() {
  log "Installing NVIDIA CUDA keyring…"
  tmp=$(mktemp -d)
  cd "$tmp"

  wget -q "${CUDA_BASE}/cuda-keyring_1.1-1_all.deb"
  dpkg -i cuda-keyring_1.1-1_all.deb

  cd /
  rm -rf "$tmp"
  apt update
}

# ==========================================================
# Secure Boot MOK automation
# ==========================================================
secureboot() {
  if ! mokutil --sb-state 2>/dev/null | grep -qi enabled; then
    return 0
  fi

  log "Secure Boot enabled — preparing MOK enrollment…"
  MOK_DIR="/root/nvidia-mok"
  mkdir -p "$MOK_DIR"
  cd "$MOK_DIR"

  if [[ ! -f MOK.key ]]; then
    openssl req -new -x509 -newkey rsa:2048 \
      -keyout MOK.key -out MOK.crt -nodes -days 3650 \
      -subj "/CN=NVIDIA Kernel Modules/"
    openssl x509 -outform DER -in MOK.crt -out MOK.der
  fi

  mokutil --import MOK.der || true
  warn "You MUST enroll the MOK on next reboot (blue screen)."
}

# ==========================================================
# install
# ==========================================================
install() {
  log "Installing NVIDIA driver packages…"

  if $FORCE_DKMS; then
    apt install -y nvidia-kernel-open-dkms cuda-drivers
  else
    apt install -y cuda-drivers
  fi
}

# ==========================================================
# APT pinning
# ==========================================================
pin_driver() {
  $PIN_DRIVER || return 0

  log "Pinning NVIDIA driver version…"
  VERSION=$(dpkg-query -W -f='${Version}\n' nvidia-driver 2>/dev/null | head -n1 || true)
  [[ -n "$VERSION" ]] || warn "Could not detect driver version for pinning."

  cat >/etc/apt/preferences.d/nvidia-pin <<EOF
Package: nvidia-driver* cuda-drivers* nvidia-kernel-* libnvidia-*
Pin: version *
Pin-Priority: 1001
EOF
}

# ==========================================================
# Desktop / Wayland config
# ==========================================================
config_desktop() {
  $HEADLESS && return 0

  log "Configuring Wayland (GDM)…"
  GDM="/etc/gdm3/daemon.conf"

  sed -i 's/^#WaylandEnable=false/WaylandEnable=true/' "$GDM" 2>/dev/null || true
  sed -i 's/^WaylandEnable=false/WaylandEnable=true/' "$GDM" 2>/dev/null || true

  cat >/etc/udev/rules.d/99-nvidia-wayland.rules <<EOF
ENV{NVIDIA_DRIVER_CAPABILITIES}="all"
EOF

  udevadm control --reload-rules
  udevadm trigger
}

# ==========================================================
# Install-time verification (NO runtime checks)
# ==========================================================
verify_install() {
  log "Verifying NVIDIA installation (pre-reboot)…"

  if ! command -v nvidia-smi >/dev/null; then
    die "nvidia-smi not installed (userspace missing)"
  fi

  if ! find /lib/modules -type f -name 'nvidia*.ko*' | grep -q .; then
    die "NVIDIA kernel modules not found on disk"
  fi

  log "Installation verified. Reboot required."
}

# ==========================================================
# Post-reboot verification
# ==========================================================
verify_runtime() {
  log "Post-reboot NVIDIA runtime verification…"

  command -v nvidia-smi >/dev/null || die "nvidia-smi missing"
  nvidia-smi || die "NVIDIA driver not functional"

  lsmod | grep -qi nvidia || die "NVIDIA kernel module not loaded"

  log "NVIDIA driver fully operational."
}

# ==========================================================
# Entrypoint
# ==========================================================
case "$ACTION" in
all)
  deps
  preconfig
  secureboot
  install
  pin_driver
  config_desktop
  verify_install
  ;;
verify)
  verify_runtime
  ;;
*)
  die "Usage: $0 {all|verify} [--headless|--server] [--force-dkms] [--pin-driver]"
  ;;
esac
