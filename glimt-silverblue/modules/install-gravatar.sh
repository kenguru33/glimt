#!/usr/bin/env bash
# Glimt module: set-user-avatar (Silverblue-safe)
#
# Exit codes:
#   0 = success
#   2 = controlled stop (needs interactive sudo or input)
#   1 = real failure

MODULE_NAME="set-user-avatar"

set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] failed at line $LINENO" >&2' ERR

ACTION="${1:-all}"
SIZE="${2:-256}"

HOME_DIR="$HOME"
CONFIG_DIR="$HOME_DIR/.config/glimt"

GRAVATAR_CONFIG="$CONFIG_DIR/set-user-avatar.config"
GIT_STATE="$CONFIG_DIR/git.state"

FACE_IMAGE="$HOME_DIR/.face"

ICON_DIR="/var/lib/AccountsService/icons"
USER_FILE="/var/lib/AccountsService/users/$USER"

log() { echo "[$MODULE_NAME] $*"; }

mkdir -p "$CONFIG_DIR"

# --------------------------------------------------
# Reconfigure (wipe state only, HARD STOP)
# --------------------------------------------------
if [[ "$ACTION" == "reconfigure" ]]; then
  rm -f "$GRAVATAR_CONFIG"
  log "♻️  Gravatar state removed"
  exit 0
fi

# --------------------------------------------------
# Load Git email (optional)
# --------------------------------------------------
GIT_EMAIL=""
if [[ -f "$GIT_STATE" ]]; then
  # shellcheck disable=SC1090
  source "$GIT_STATE"
  GIT_EMAIL="${GIT_EMAIL:-}"
fi

# --------------------------------------------------
# Load or prompt for Gravatar email
# --------------------------------------------------
EMAIL=""

if [[ -f "$GRAVATAR_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$GRAVATAR_CONFIG"
  EMAIL="${gravatar_email:-}"
fi

if [[ -z "$EMAIL" ]]; then
  if [[ ! -t 0 ]]; then
    echo
    echo "ℹ️  Avatar setup requires user input."
    echo "👉 Run interactively:"
    echo "   set-user-avatar reconfigure"
    echo
    exit 2
  fi

  echo
  echo "🖼 Gravatar (login avatar)"

  if [[ -n "$GIT_EMAIL" ]]; then
    read -rp "👉 Use same email as Git ($GIT_EMAIL)? [Y/n]: " reply
    case "$reply" in
    n | N | no | NO) ;;
    *) EMAIL="$GIT_EMAIL" ;;
    esac
  fi

  if [[ -z "$EMAIL" ]]; then
    while true; do
      read -rp "📧 Gravatar email: " EMAIL
      [[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] && break
      echo "❌ Invalid email"
    done
  fi

  echo "gravatar_email=\"$EMAIL\"" >"$GRAVATAR_CONFIG"
  log "💾 Gravatar email saved"
fi

# --------------------------------------------------
# Download avatar
# --------------------------------------------------
HASH="$(printf '%s' "$EMAIL" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1)"
URL="https://www.gravatar.com/avatar/$HASH?s=$SIZE&d=identicon"

log "Downloading avatar"
curl -fsSL "$URL" -o "$FACE_IMAGE"

# --------------------------------------------------
# GNOME session avatar
# --------------------------------------------------
if command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.account-service account-picture "$FACE_IMAGE" || true
  log "GNOME session avatar set"
fi

# --------------------------------------------------
# GDM avatar (idempotent)
# --------------------------------------------------
if [[ -f "$USER_FILE" ]] && grep -q "^Icon=$ICON_DIR/$USER$" "$USER_FILE" 2>/dev/null; then
  log "GDM avatar already set"
  exit 0
fi

log "Attempting to set GDM avatar (requires sudo)"

sudo -n install -m 644 "$FACE_IMAGE" "$ICON_DIR/$USER" 2>/dev/null || {
  echo
  echo "🔐 GDM avatar requires administrator access."
  echo "👉 Re-run setup interactively or run:"
  echo "   sudo set-user-avatar"
  echo
  exit 2
}

sudo -n bash -c "cat > '$USER_FILE' <<EOF
[User]
Icon=$ICON_DIR/$USER
EOF" || {
  echo "🔐 Failed to write AccountsService config"
  exit 2
}

sudo -n systemctl restart accounts-daemon || {
  echo "🔐 Failed to restart accounts-daemon"
  exit 2
}

log "GDM avatar installed"
exit 0
