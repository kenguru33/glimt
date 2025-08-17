#!/usr/bin/env bash
# modules/debian/install-virtualization-suite.sh
# Debian 13 "Trixie": Full virtualization suite via APT (GNOME Boxes + QEMU/KVM + libvirt + OVMF + TPM + SPICE).
# Actions: all | deps | install | config | clean | purge-flatpak
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="virtualization-suite"
ACTION="${1:-all}"
USER_NAME="${SUDO_USER:-$USER}"

# --- Guard: Debian only (Trixie script, but allow any Debian) ---
is_debian() {
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo -E -- "$0" "$ACTION"
  fi
}

# --- Packages (Trixie names) ---
DEPS_APT=(curl gnupg)

MAIN_APT_PACKAGES=(
  gnome-boxes
  qemu-system qemu-utils
  libvirt-daemon libvirt-daemon-system libvirt-clients virtinst
  virt-viewer
  ovmf                      # UEFI firmware
  swtpm swtpm-tools         # TPM 2.0 (e.g. Win11)
  spice-vdagent spice-webdavd usbredirect  # SPICE integration + USB redirection
)

# --- Steps ---
deps() {
  echo "🔧 [$MODULE_NAME] Installing deps…"
  apt-get update -y
  apt-get install -y "${DEPS_APT[@]}"
}

install_pkgs() {
  echo "➕ [$MODULE_NAME] Installing virtualization suite (APT)…"
  apt-get update -y
  apt-get install -y "${MAIN_APT_PACKAGES[@]}"
}

config() {
  echo "⚙️ [$MODULE_NAME] Enabling libvirt services…"
  systemctl enable --now libvirtd.service
  systemctl enable --now virtlogd.service

  echo "👥 [$MODULE_NAME] Adding '$USER_NAME' to groups: kvm, libvirt…"
  for grp in kvm libvirt; do
    getent group "$grp" >/dev/null || groupadd "$grp"
    usermod -aG "$grp" "$USER_NAME"
  done

  if command -v virsh >/dev/null 2>&1; then
    echo "🌐 [$MODULE_NAME] Ensuring 'default' NAT network is up…"
    if virsh net-info default >/dev/null 2>&1; then
      virsh net-start default >/dev/null 2>&1 || true
      virsh net-autostart default >/dev/null 2>&1 || true
    else
      echo "ℹ️ Creating a basic 'default' NAT network…"
      cat >/tmp/default-net.xml <<'XML'
<network>
  <name>default</name>
  <bridge name="virbr0" stp="on" delay="0"/>
  <ip address="192.168.122.1" netmask="255.255.255.0">
    <dhcp><range start="192.168.122.2" end="192.168.122.254"/></dhcp>
  </ip>
</network>
XML
      virsh net-define /tmp/default-net.xml
      virsh net-start default
      virsh net-autostart default
      rm -f /tmp/default-net.xml
    fi
  fi

  echo "🧪 [$MODULE_NAME] Quick checks…"
  if [[ -e /dev/kvm ]]; then
    echo "  ✔ /dev/kvm present"
  else
    echo "  ⚠ /dev/kvm missing (enable VT-x/AMD-V in BIOS/UEFI, then reboot)."
  fi
  command -v virt-host-validate >/dev/null 2>&1 && virt-host-validate || echo "  (virt-host-validate unavailable)"
  echo "✅ [$MODULE_NAME] Done. Log out/in so new group memberships apply."
}

clean() {
  echo "🧹 [$MODULE_NAME] Removing virtualization suite…"
  apt-get purge -y gnome-boxes || true
  # Remove the stack as well (comment out if you want to keep it)
  apt-get purge -y qemu-system qemu-utils libvirt-daemon libvirt-daemon-system libvirt-clients virtinst \
                    virt-viewer ovmf swtpm swtpm-tools spice-vdagent spice-webdavd usbredirect || true
  apt-get autoremove -y
  echo "✅ [$MODULE_NAME] Cleaned."
}

purge_flatpak() {
  # Optional convenience: remove Flatpak Boxes if it exists from earlier experiments
  if command -v flatpak >/dev/null 2>&1; then
    echo "🧽 [$MODULE_NAME] Uninstalling Flatpak org.gnome.Boxes (if present)…"
    sudo -u "$USER_NAME" flatpak uninstall -y org.gnome.Boxes || true
  else
    echo "ℹ️ Flatpak not installed; nothing to purge."
  fi
}

all() { deps; install_pkgs; config; }

# --- Entry ---
if ! is_debian; then
  echo "❌ Unsupported OS (Debian only)."
  exit 1
fi

require_root

case "$ACTION" in
  deps)           deps ;;
  install)        install_pkgs ;;
  config)         config ;;
  clean)          clean ;;
  purge-flatpak)  purge_flatpak ;;
  all)            all ;;
  *) echo "Usage: $0 [all|deps|install|config|clean|purge-flatpak]"; exit 2 ;;
esac
