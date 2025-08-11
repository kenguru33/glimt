#!/bin/bash
set -e

trap 'gum log --level error "❌ An error occurred. Exiting."' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES="$SCRIPT_DIR/modules"

# === Make sure system is updated ===
$MODULES/system-update.sh install

clear

# === Run the banner if available ===
if [[ -x "$MODULES/banner.sh" ]]; then
  "$MODULES/banner.sh"
fi

# === Confirm install ===
if ! gum confirm "🤔 Do you want to continue with the installation?"; then
  gum log --level info "🚫 Installation cancelled by user."
  exit 0
fi

# === Check for required scripts ===
if [[ ! -x "$MODULES/check-sudo.sh" ]]; then
  gum style \
    --border normal \
    --margin "1" \
    --padding "1 3" \
    --foreground 1 \
    --border-foreground 9 \
    "❌ Missing or non-executable: $MODULES/check-sudo.sh"
  exit 1
fi

# === Run sudo check ===
"$MODULES/check-sudo.sh"

# === Parse flags and action ===
FLAGS=()
ACTION=""

for arg in "$@"; do
  case "$arg" in
    --verbose|--quiet)
      FLAGS+=("$arg")
      ;;
    all|install|config|clean)
      ACTION="$arg"
      ;;
    *)
      gum log --level error "❌ Unknown argument: $arg"
      exit 1
      ;;
  esac
done

# Default action if not specified
ACTION="${ACTION:-all}"

# === Check user-profile.sh exists ===
if [[ ! -x "$MODULES/user-profile.sh" ]]; then
  gum style \
    --border normal \
    --margin "1" \
    --padding "1 3" \
    --foreground 1 \
    --border-foreground 9 \
    "❌ Missing or non-executable: $MODULES/user-profile.sh"
  exit 1
fi

# === Ask user for name/email ===
"$MODULES/user-profile.sh" all

clear

# === GNOME or terminal path ===
if command -v gnome-shell &>/dev/null; then
  gum log --level info "GNOME desktop detected. Including full desktop environment setup."
  "$SCRIPT_DIR/install-terminal.sh" "${FLAGS[@]}" "$ACTION"
  "$SCRIPT_DIR/install-desktop.sh" "${FLAGS[@]}" "$ACTION"
  "$SCRIPT_DIR/install-optional.sh" "${FLAGS[@]}" "$ACTION"
  DESKTOP_STATUS=$?
else
  gum log --level info "**GNOME** not detected. Running terminal only installation."
  "$SCRIPT_DIR/install-terminal.sh" "${FLAGS[@]}" "$ACTION"
  "$SCRIPT_DIR/install-optional.sh" "${FLAGS[@]}" "$ACTION"
  DESKTOP_STATUS=$?
fi

# === Final status ===
if [[ $DESKTOP_STATUS -eq 0 ]]; then
  gum log --level info "✅ Installation completed successfully."
  if command -v gnome-shell &>/dev/null; then
    gum log --level info "🔁 Please log out and back in to apply all GNOME desktop changes."
  fi
else
  gum log --level error "❌ Setup failed during installation."
  exit $DESKTOP_STATUS
fi
