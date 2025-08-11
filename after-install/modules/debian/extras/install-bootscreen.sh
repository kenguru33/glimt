#!/bin/bash
set -e
trap 'echo "❌ Plymouth installation failed. Exiting." >&2' ERR

MODULE_NAME="plymouth"
ACTION="${1:-all}"

DEFAULT_THEME="bgrt"
PLYMOUTH_THEME_CONF="/etc/plymouth/plymouthd.conf"
GRUB_DEFAULT="/etc/default/grub"

# === Step: deps ===
deps() {
  echo "📦 Installing Plymouth and required packages..."
  sudo apt update
  sudo apt install -y plymouth plymouth-themes grub2
}

# === Step: install ===
install() {
  echo "🎨 Setting Plymouth theme: $DEFAULT_THEME"
  if plymouth-set-default-theme --list | grep -qx "$DEFAULT_THEME"; then
    sudo plymouth-set-default-theme -R "$DEFAULT_THEME"
  else
    echo "⚠️ Theme '$DEFAULT_THEME' not found. Available themes:"
    plymouth-set-default-theme --list
    exit 1
  fi
}

# === Step: config ===
config() {
  echo "⚙️ Configuring GRUB for Plymouth..."

  if ! grep -q "splash" "$GRUB_DEFAULT"; then
    sudo sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT=.*\)"/\1 splash"/' "$GRUB_DEFAULT"
  fi

  echo "🔄 Updating GRUB..."
  sudo update-grub

  echo "📁 Updating initramfs..."
  sudo update-initramfs -u
}

# === Step: clean ===
clean() {
  echo "🧹 Removing Plymouth..."
  sudo apt purge -y plymouth plymouth-themes
  sudo rm -f "$PLYMOUTH_THEME_CONF"

  echo "🧼 Reverting GRUB_CMDLINE_LINUX_DEFAULT..."
  sudo sed -i 's/ splash//' "$GRUB_DEFAULT"
  sudo update-grub
  sudo update-initramfs -u
}

# === Entrypoint ===
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
  echo "❌ Unknown action: $ACTION"
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
