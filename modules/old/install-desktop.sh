#!/bin/bash
set -e

trap 'echo "❌ An error occurred. Exiting." >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES="$SCRIPT_DIR/modules"

# === Default SHOW_OUTPUT is 0 (quiet) ===
SHOW_OUTPUT="${SHOW_OUTPUT:-0}"

# === Parse optional flags ===
for arg in "$@"; do
  case "$arg" in
    --verbose)
      SHOW_OUTPUT=1
      shift
      ;;
    --quiet)
      SHOW_OUTPUT=0
      shift
      ;;
  esac
done

# === Determine action (e.g. all, install, config, clean) ===
ACTION="${1:-all}"

# === Utility function for conditional spinner ===
run_with_spinner() {
  TITLE="$1"
  CMD="$2"

  if [[ "$SHOW_OUTPUT" == "1" ]]; then
    echo "▶️ $TITLE"
    bash -c "$CMD"
  else
    gum spin --title "$TITLE" -- bash -c "$CMD"
  fi
}

case "$ACTION" in
  all)
    run_with_spinner "Installing user profile image..." "$MODULES/install-gravatar.sh all"
    run_with_spinner "Installing GNOME config..." "$MODULES/install-gnome-config.sh all"
    run_with_spinner "Installing Papirus icon theme..." "$MODULES/install-papirus-icon-theme.sh all"
    run_with_spinner "Installing GNOME extensions..." "$MODULES/install-gnome-extensions.sh all"
#    run_with_spinner "Installing NVIDIA driver..." "$MODULES/install-nvidia.sh all"
    ;;
  install)
    run_with_spinner "Installing user profile image..." "$MODULES/install-gravatar.sh install"
    run_with_spinner "Installing GNOME config..." "$MODULES/install-gnome-config.sh install"
    run_with_spinner "Installing icon theme..." "$MODULES/install-papirus-icon-theme.sh install"
    run_with_spinner "Installing GNOME extensions..." "$MODULES/install-gnome-extensions.sh install"
    run_with_spinner "Installing NVIDIA driver..." "$MODULES/install-nvidia.sh install"
    ;;
  config)
    run_with_spinner "Cleaning user profile image..." "$MODULES/install-gravatar.sh config"
    run_with_spinner "Configuring GNOME..." "$MODULES/install-gnome-config.sh config"
    run_with_spinner "Configuring icon theme..." "$MODULES/install-papirus-icon-theme.sh config"
    run_with_spinner "Configuring GNOME extensions..." "$MODULES/install-gnome-extensions.sh config"
    run_with_spinner "Configuring NVIDIA driver..." "$MODULES/install-nvidia.sh config"
    ;;
  clean)
    run_with_spinner "Cleaning user profile image..." "$MODULES/install-gravatar.sh clean"
    run_with_spinner "Cleaning GNOME config..." "$MODULES/install-gnome-config.sh clean"
    run_with_spinner "Cleaning icon theme..." "$MODULES/install-papirus-icon-theme.sh clean"
    run_with_spinner "Cleaning GNOME extensions..." "$MODULES/install-gnome-extensions.sh clean"
    run_with_spinner "Cleaning NVIDIA driver..." "$MODULES/install-nvidia.sh clean"
    ;;
  *)
    echo "Usage: $0 [--verbose|--quiet] [all|install|config|clean]"
    exit 1
    ;;
esac

echo "✅ Desktop environment '$ACTION' completed successfully!"
