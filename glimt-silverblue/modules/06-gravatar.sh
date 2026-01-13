#!/usr/bin/env bash
# Glimt module: set-user-avatar (Silverblue-safe)
# Actions: all | reconfigure

set -Eeuo pipefail
trap 'echo "❌ [set-user-avatar] failed at line $LINENO" >&2' ERR

MODULE_NAME="set-user-avatar"
ACTION="${1:-all}"
SIZE="${2:-256}"

# --------------------------------------------------
# Resolve real user (CRITICAL when run via sudo)
# --------------------------------------------------
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
CONFIG_DIR="$HOME_DIR/.config/glimt"

GRAVATAR_CONFIG="$CONFIG_DIR/set-user-avatar.config"
GIT_STATE="$CONFIG_DIR/git.state"

FACE_IMAGE="$HOME_DIR/.face"

ICON_DIR="/var/lib/AccountsService/icons"
USER_FILE="/var/lib/AccountsService/users/$REAL_USER"

log() { echo "[$MODULE_NAME] $*"; }
die() {
  echo "❌ [$MODULE_NAME] $*" >&2
  exit 1
}

mkdir -p "$CONFIG_DIR"

# --------------------------------------------------
# sudo handling (REUSE ticket, prompt only if needed)
# --------------------------------------------------
ensure_sudo() {
  if [[ "$EUID" -ne 0 ]]; then
    sudo -v || die "Administrator access required"
  fi
}

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

log "⬇️  Downloading avatar"
curl -fsSL "$URL" -o "$FACE_IMAGE"

# --------------------------------------------------
# GNOME session avatar (user scope)
# --------------------------------------------------
if command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.account-service account-picture "$FACE_IMAGE" || true
  log "🧑 GNOME session avatar set"
fi

# --------------------------------------------------
# GDM avatar (AccountsService, system scope)
# --------------------------------------------------
ensure_sudo

log "🖥 Setting GDM avatar for user: $REAL_USER"

# Install icon (idempotent)
install -m 644 "$FACE_IMAGE" "$ICON_DIR/$REAL_USER"

# Write user file
cat >"$USER_FILE" <<EOF
[User]
Icon=$ICON_DIR/$REAL_USER
EOF

# Restart AccountsService only if running
systemctl is-active accounts-daemon >/dev/null 2>&1 &&
  systemctl restart accounts-daemon

log "✅ GDM avatar installed"
exit 0
