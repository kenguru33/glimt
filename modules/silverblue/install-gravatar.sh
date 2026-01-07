#!/usr/bin/env bash
# Glans module: set-user-avatar (Silverblue-safe)
#
# Exit codes:
#   0 = success (GNOME + GDM avatar set)
#   2 = controlled stop (needs interactive sudo)
#   1 = real failure

set -euo pipefail

MODULE_NAME="set-user-avatar"
ACTION="${1:-all}"
SIZE="${2:-256}"

HOME_DIR="$HOME"
CONFIG_DIR="$HOME_DIR/.config/glimt"
CONFIG_FILE="$CONFIG_DIR/set-user-avatar.config"
FACE_IMAGE="$HOME_DIR/.face"

ICON_DIR="/var/lib/AccountsService/icons"
USER_FILE="/var/lib/AccountsService/users/$USER"

log() { echo "[$MODULE_NAME] $*"; }
die() { echo "❌ $*" >&2; exit 1; }

mkdir -p "$CONFIG_DIR"

# --------------------------------------------------
# Load or prompt for email (INTERACTIVE ONLY)
# --------------------------------------------------
EMAIL=""

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
  EMAIL="${gravatar_email:-}"
fi

if [[ -z "$EMAIL" ]]; then
  if [[ ! -t 0 ]]; then
    echo
    echo "ℹ️  Avatar setup requires user input."
    echo "👉 Run interactively:"
    echo "   install-gravatar.sh reconfigure"
    echo
    exit 2
  fi

  while true; do
    read -rp "📧 Email for Gravatar: " EMAIL
    [[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] && break
    echo "❌ Invalid email"
  done

  echo "gravatar_email=\"$EMAIL\"" >"$CONFIG_FILE"
fi

# --------------------------------------------------
# Download avatar
# --------------------------------------------------
HASH="$(printf '%s' "$EMAIL" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1)"
URL="https://www.gravatar.com/avatar/$HASH?s=$SIZE&d=identicon"

log "Downloading avatar"
curl -fsSL "$URL" -o "$FACE_IMAGE"

# --------------------------------------------------
# GNOME session avatar (user space)
# --------------------------------------------------
if command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.account-service account-picture "$FACE_IMAGE" || true
  log "GNOME session avatar set"
fi

# --------------------------------------------------
# Check if GDM avatar already set
# --------------------------------------------------
if [[ -f "$USER_FILE" ]] && grep -q "^Icon=$ICON_DIR/$USER$" "$USER_FILE" 2>/dev/null; then
  log "GDM avatar already set"
  exit 0
fi

# --------------------------------------------------
# GDM avatar (NO PROMPT — sudo -n only)
# --------------------------------------------------
log "Attempting to set GDM avatar (requires sudo)"

sudo -n install -m 644 "$FACE_IMAGE" "$ICON_DIR/$USER" 2>/dev/null || {
  echo
  echo "🔐 GDM avatar requires administrator access."
  echo "👉 Re-run setup interactively or run:"
  echo "   sudo install-gravatar.sh"
  echo
  exit 2
}

sudo -n tee "$USER_FILE" >/dev/null <<EOF || {
[User]
Icon=$ICON_DIR/$USER
EOF
  echo "🔐 Failed to write AccountsService config"
  exit 2
}

sudo -n systemctl restart accounts-daemon || {
  echo "🔐 Failed to restart accounts-daemon"
  exit 2
}

log "GDM avatar installed"
exit 0
