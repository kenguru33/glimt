#!/bin/bash
set -e

ACTION="${1:-all}"
MODULE="flatpak"
REMOTE_NAME="flathub"
REMOTE_URL="https://flathub.org/repo/flathub.flatpakrepo"

config_flatpak() {
  echo "⚙️  Ensuring Flathub is set up..."
  if ! flatpak remote-list | grep -q "^${REMOTE_NAME}"; then
    sudo flatpak remote-add --if-not-exists "$REMOTE_NAME" "$REMOTE_URL"
  fi
  echo "✅ Flatpak is configured with Flathub."
}

clean_flatpak() {
  echo "🧹 Removing Flatpak and Flathub..."
  sudo flatpak remote-delete "$REMOTE_NAME" || true
  sudo dnf remove -y flatpak || true
  echo "✅ Flatpak removed."
}

# === Entry point ===
case "$ACTION" in
deps) ;;
install) ;;
config)
  config_flatpak
  ;;
clean)
  clean_flatpak
  ;;
all)
  config_flatpak
  ;;
*)
  echo "Usage: $0 {deps|install|config|clean|all}"
  exit 1
  ;;
esac
