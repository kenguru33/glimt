#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="gnome-boxes-tune"
ACTION="${1:-all}"
TS="$(date +%Y%m%d%H%M%S)"

# ==== Debian-only guard ====
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || { echo "❌ Debian only."; exit 1; }
else
  echo "❌ Cannot detect OS."
  exit 1
fi

# ==== Detect CPU/GPU ====
CPU_VENDOR="$(lscpu | awk -F: '/Vendor ID/{gsub(/^[ \t]+/,"",$2); print $2}')"
GPU_VENDOR="$(lspci -nn | grep -i ' VGA ' | grep -oE 'NVIDIA|AMD|Intel' | head -n1 || true)"

# ==== Paths ====
SESSION_QEMU_DIR="$HOME/.config/libvirt/qemu"            # Boxes session domains
BOXES_STATE_DIR="$HOME/.local/share/gnome-boxes"         # Boxes state
TUNED_CONF="$HOME/.config/gnome-boxes/tuned.conf"        # (optional) Boxes display defaults
BACKUP_DIR="$HOME/.local/share/glans/backups/$MODULE_NAME/$TS"
LAUNCHER_BIN="$HOME/.local/bin/boxes-nvidia"
DESKTOP_DIR="$HOME/.local/share/applications"
DESKTOP_FILE="$DESKTOP_DIR/boxes-nvidia.desktop"

mkdir -p "$BACKUP_DIR" "$DESKTOP_DIR" "$HOME/.local/bin"

msg() { printf "• %s\n" "$*"; }

add_user_groups() {
  local u="$USER"
  for g in "$@"; do
    if ! id -nG "$u" | tr ' ' '\n' | grep -qx "$g"; then
      sudo usermod -aG "$g" "$u"
      msg "Added $u to group: $g (re-login required)"
    fi
  done
}

enable_kvm_module() {
  case "$CPU_VENDOR" in
    GenuineIntel) sudo modprobe kvm_intel || true ;;
    AuthenticAMD) sudo modprobe kvm_amd  || true ;;
    *) msg "Unknown CPU vendor ($CPU_VENDOR). Skipping kvm_* modprobe." ;;
  esac
  [[ -e /dev/kvm ]] || { echo "❌ /dev/kvm missing. Enable VT-x/AMD-V in BIOS/UEFI."; exit 1; }
}

# ==== XML-safe patcher using xmlstarlet ====
patch_domain_xml() {
  local xml="$1"
  [[ -f "$xml" ]] || return 0

  # Validate XML; skip if invalid
  if ! xmlstarlet val -q "$xml"; then
    msg "  ! Skipping invalid XML: $xml"
    return 0
  fi

  # backup
  local rel="${xml#"$HOME"/}"
  local bak="$BACKUP_DIR/${rel//\//_}.bak"
  cp -a "$xml" "$bak"

  # vCPU >= 2 with placement="static"
  if xmlstarlet sel -t -v "count(/domain/vcpu)" -n "$xml" | grep -q '^0$'; then
    xmlstarlet ed -L -s /domain -t elem -n vcpu -v 2 "$xml"
    xmlstarlet ed -L -i /domain/vcpu -t attr -n placement -v static "$xml"
  else
    local cur="$(xmlstarlet sel -t -v "/domain/vcpu" -n "$xml" | head -n1 || echo 1)"
    [[ "${cur:-1}" -lt 2 ]] && xmlstarlet ed -L -u "/domain/vcpu" -v 2 "$xml"
    xmlstarlet ed -L -i /domain/vcpu -t attr -n placement -v static "$xml" 2>/dev/null || true
  fi

  # memory/currentMemory = 4096 MiB
  for node in memory currentMemory; do
    if xmlstarlet sel -t -v "count(/domain/$node)" -n "$xml" | grep -q '^0$'; then
      xmlstarlet ed -L -s /domain -t elem -n "$node" -v 4096 "$xml"
      xmlstarlet ed -L -i "/domain/$node" -t attr -n unit -v MiB "$xml"
    else
      xmlstarlet ed -L -u "/domain/$node" -v 4096 "$xml"
      xmlstarlet ed -L -u "/domain/$node/@unit" -v MiB "$xml" 2>/dev/null || \
      xmlstarlet ed -L -i "/domain/$node" -t attr -n unit -v MiB "$xml"
    fi
  done

  # cpu mode='host-passthrough'
  if xmlstarlet sel -t -v "count(/domain/cpu)" -n "$xml" | grep -q '^0$'; then
    xmlstarlet ed -L -s /domain -t elem -n cpu -v "" "$xml"
  fi
  xmlstarlet ed -L -u "/domain/cpu/@mode" -v host-passthrough "$xml" 2>/dev/null || \
  xmlstarlet ed -L -i "/domain/cpu" -t attr -n mode -v host-passthrough "$xml"

  # Disk virtio (first disk only, if present) + prefer qcow2
  if xmlstarlet sel -t -v "count(/domain/devices/disk[@device='disk']/target)" -n "$xml" | grep -q '^[1-9]'; then
    xmlstarlet ed -L -u "/domain/devices/disk[@device='disk']/target/@bus" -v virtio "$xml" 2>/dev/null || true
    xmlstarlet ed -L -u "/domain/devices/disk[@device='disk']/target/@dev" -v vda "$xml" 2>/dev/null || true
    if xmlstarlet sel -t -v "count(/domain/devices/disk[@device='disk']/driver/@type)" -n "$xml" | grep -q '^[1-9]'; then
      xmlstarlet ed -L -u "/domain/devices/disk[@device='disk']/driver/@type" -v qcow2 "$xml" 2>/dev/null || true
    fi
  fi

  # Network model virtio (first interface)
  if xmlstarlet sel -t -v "count(/domain/devices/interface/model)" -n "$xml" | grep -q '^[1-9]'; then
    xmlstarlet ed -L -u "/domain/devices/interface/model/@type" -v virtio "$xml" 2>/dev/null || true
  fi

  # Video virtio + accel3d + heads=1
  if xmlstarlet sel -t -v "count(/domain/devices/video)" -n "$xml" | grep -q '^0$'; then
    xmlstarlet ed -L -s /domain/devices -t elem -n video -v "" "$xml"
  fi
  if xmlstarlet sel -t -v "count(/domain/devices/video/model)" -n "$xml" | grep -q '^0$'; then
    xmlstarlet ed -L -s /domain/devices/video -t elem -n model -v "" "$xml"
  fi
  xmlstarlet ed -L -u "/domain/devices/video/model/@type" -v virtio "$xml" 2>/dev/null || \
  xmlstarlet ed -L -i "/domain/devices/video/model" -t attr -n type -v virtio "$xml"
  xmlstarlet ed -L -u "/domain/devices/video/model/@accel3d" -v yes "$xml" 2>/dev/null || \
  xmlstarlet ed -L -i "/domain/devices/video/model" -t attr -n accel3d -v yes "$xml"
  xmlstarlet ed -L -u "/domain/devices/video/model/@heads" -v 1 "$xml" 2>/dev/null || \
  xmlstarlet ed -L -i "/domain/devices/video/model" -t attr -n heads -v 1 "$xml"

  # SPICE graphics + GL rendernode
  if xmlstarlet sel -t -v "count(/domain/devices/graphics[@type='spice'])" -n "$xml" | grep -q '^0$'; then
    xmlstarlet ed -L -s /domain/devices -t elem -n graphics -v "" "$xml"
    xmlstarlet ed -L -i /domain/devices/graphics -t attr -n type -v spice "$xml"
    xmlstarlet ed -L -i /domain/devices/graphics -t attr -n autoport -v yes "$xml"
  else
    xmlstarlet ed -L -u "/domain/devices/graphics[@type='spice']/@autoport" -v yes "$xml"
  fi
  if xmlstarlet sel -t -v "count(/domain/devices/graphics/gl)" -n "$xml" | grep -q '^0$'; then
    xmlstarlet ed -L -s "/domain/devices/graphics[@type='spice']" -t elem -n gl -v "" "$xml"
  fi
  xmlstarlet ed -L -u "/domain/devices/graphics[@type='spice']/gl/@enable" -v yes "$xml" 2>/dev/null || \
  xmlstarlet ed -L -i "/domain/devices/graphics[@type='spice']/gl" -t attr -n enable -v yes "$xml"
  xmlstarlet ed -L -u "/domain/devices/graphics[@type='spice']/gl/@rendernode" -v /dev/dri/renderD128 "$xml" 2>/dev/null || \
  xmlstarlet ed -L -i "/domain/devices/graphics[@type='spice']/gl" -t attr -n rendernode -v /dev/dri/renderD128 "$xml"

  msg "    Patched OK: $xml"
}

# ==== Phase: deps ====
deps() {
  msg "Installing Debian deps (GNOME Boxes + KVM + SPICE + VirGL + xmlstarlet)"
  sudo apt update
  sudo apt install -y \
    gnome-boxes \
    qemu-system-x86 qemu-utils \
    libvirt-daemon libvirt-daemon-system libvirt-clients \
    virt-manager spice-vdagent spice-webdavd \
    libspice-server1 libspice-client-glib-2.0-8 libspice-client-gtk-3.0-5 \
    libgl1-mesa-dri mesa-vulkan-drivers mesa-utils \
    libvirglrenderer1 \
    xmlstarlet
}

# ==== Phase: install ====
install() {
  msg "Enabling KVM + libvirt"
  enable_kvm_module
  sudo systemctl enable --now libvirtd

  # Groups: kvm (accel), libvirt (mgmt), render (DRI render node)
  add_user_groups kvm libvirt render
}

# ==== Phase: config ====
config() {
  # Optional display defaults; harmless if Boxes ignores it
  msg "Writing GNOME Boxes display defaults"
  mkdir -p "$(dirname "$TUNED_CONF")"
  cp -a "$TUNED_CONF" "$BACKUP_DIR/tuned.conf.bak" 2>/dev/null || true
  cat > "$TUNED_CONF" <<'EOF'
[display]
accel3d=true
accel3d_renderer=gl
gl_version=4.6
EOF

  # NVIDIA optional EGL launcher
  if [[ "$GPU_VENDOR" == "NVIDIA" ]]; then
    msg "NVIDIA detected — ensuring EGL libs and installing EGL launcher"
    sudo apt install -y libegl1 libgles2
    cat > "$LAUNCHER_BIN" <<'EOS'
#!/bin/bash
set -euo pipefail
export __GLX_VENDOR_LIBRARY_NAME=nvidia
exec gnome-boxes "$@"
EOS
    chmod +x "$LAUNCHER_BIN"
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=GNOME Boxes (NVIDIA EGL)
GenericName=Virtual Machine Manager
Comment=Run GNOME Boxes with NVIDIA EGL path
Exec=$LAUNCHER_BIN
Icon=org.gnome.Boxes
Terminal=false
Categories=System;Emulator;X-GNOME-Utilities;
Keywords=virtualization;virt;vm;
StartupNotify=true
EOF
    command -v update-desktop-database >/dev/null && update-desktop-database "$DESKTOP_DIR" || true
  fi

  # Patch existing session domains
  msg "Tuning existing GNOME Boxes session domains (if any)"
  if [[ -d "$SESSION_QEMU_DIR" ]]; then
    shopt -s nullglob
    for xml in "$SESSION_QEMU_DIR"/*.xml; do
      msg "  - $xml"
      patch_domain_xml "$xml"
    done
  else
    msg "No session libvirt domains yet at $SESSION_QEMU_DIR"
  fi

  [[ -d "$BOXES_STATE_DIR" ]] && cp -a "$BOXES_STATE_DIR" "$BACKUP_DIR/gnome-boxes-state.bak" 2>/dev/null || true

  msg "Config complete. Re-login if you were newly added to kvm/libvirt/render groups."
}

# ==== Phase: clean ====
clean() {
  msg "Reverting tuned config and NVIDIA launcher"
  [[ -f "$BACKUP_DIR/tuned.conf.bak" ]] && cp -a "$BACKUP_DIR/tuned.conf.bak" "$TUNED_CONF" || rm -f "$TUNED_CONF"
  rm -f "$LAUNCHER_BIN" "$DESKTOP_FILE"

  # Restore XMLs from this run's snapshot only
  shopt -s nullglob
  for b in "$BACKUP_DIR"/*.xml.bak; do
    base="$(basename "$b" .bak)"
    target="$SESSION_QEMU_DIR/${base//_/\/}"
    [[ -f "$target" ]] && { msg "Restoring $target"; cp -a "$b" "$target"; }
  done

  msg "Clean complete. Backups remain in $HOME/.local/share/glans/backups/$MODULE_NAME/"
}

# ==== Phase: all ====
all() { deps; install; config; }

# ==== Entry ====
case "$ACTION" in
  deps|install|config|clean|all) "$ACTION" ;;
  *) echo "Usage: $0 [all|deps|install|config|clean]"; exit 1 ;;
esac
