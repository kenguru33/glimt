#!/bin/bash
set -e
trap 'echo "❌ An error occurred in FUSE installer. Exiting." >&2' ERR

MODULE_NAME="fuse"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release is missing."
  exit 1
fi

# === Fedora check: skip installer ===
if [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* ]]; then
  echo "ℹ️  $MODULE_NAME installation is not required on Fedora. Skipping."
  exit 0
fi

# === Debian/Ubuntu check: continue only if Debian-like ===
if [[ "$ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
  echo "⚠️  $MODULE_NAME installer supports only Debian-based systems. Skipping."
  exit 0
fi

# === Dependencies ===
DEPS_DEBIAN=(fuse libfuse2)

install_deps() {
  echo "📦 Installing dependencies for $MODULE_NAME..."
  sudo apt update
  sudo apt install -y "${DEPS_DEBIAN[@]}"
}

# === Install (load module, ensure group, check /dev/fuse) ===
install_fuse() {
  echo "🔌 Loading FUSE kernel module..."
  if ! lsmod | grep -q '^fuse'; then
    sudo modprobe fuse
  fi
  echo "✅ FUSE kernel module is loaded."

  echo "👥 Ensuring 'fuse' group exists..."
  if ! getent group fuse >/dev/null; then
    echo "➕ Creating 'fuse' group..."
    sudo groupadd fuse
  fi

  echo "👤 Adding user '$REAL_USER' to 'fuse' group..."
  sudo usermod -aG fuse "$REAL_USER"

  echo "🧪 Verifying /dev/fuse exists..."
  if [[ ! -e /dev/fuse ]]; then
    echo "⚠️  /dev/fuse not found. Creating with mknod..."
    sudo mknod -m 0666 /dev/fuse c 10 229
    sudo chown root:fuse /dev/fuse
  fi

  echo "✅ /dev/fuse is ready."
}

# === Config ===
config_fuse() {
  echo "⚙️  Configuring /etc/fuse.conf..."
  if [[ -f /etc/fuse.conf ]]; then
    sudo sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf
  else
    echo "user_allow_other" | sudo tee /etc/fuse.conf >/dev/null
  fi
  echo "✅ user_allow_other enabled in fuse.conf"
}

# === Clean ===
clean_fuse() {
  echo "🧹 Removing FUSE packages and configuration..."
  sudo apt purge --autoremove -y "${DEPS_DEBIAN[@]}"
  sudo rm -f /etc/fuse.conf

  if getent group fuse >/dev/null; then
    echo "➖ Removing 'fuse' group..."
    sudo groupdel fuse || echo "⚠️  Could not remove 'fuse' group (maybe in use)."
  fi

  echo "✅ FUSE uninstalled and cleaned."
}

# === Entry point ===
case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_fuse
    ;;
  config)
    config_fuse
    ;;
  clean)
    clean_fuse
    ;;
  all)
    install_deps
    install_fuse
    config_fuse
    ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
