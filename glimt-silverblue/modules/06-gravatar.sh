#!/usr/bin/env bash
# Glimt module: set-user-avatar (Silverblue-safe)
# Actions: all | reconfigure

set -Eeuo pipefail
trap 'echo "❌ [set-user-avatar] failed at line $LINENO" >&2' ERR

MODULE_NAME="set-user-avatar"
ACTION="${1:-all}"
SIZE="${2:-256}"

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
# sudo handling (reuse ticket, prompt if expired)
# --------------------------------------------------
ensure_sudo() {
  if [[ "$EUID" -ne 0 ]]; then
    sudo -v || die "Administrator access required"
  fi
}

# --------------------------------------------------
# Reconfigure
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
fi

# --------------------------------------------------
# Load / prompt email
# --------------------------------------------------
EMAIL=""
if [[ -f "$GRAVATAR_CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$GRAVATAR_CONFIG"
  EMAIL="${gravatar_email:-}"
fi

if [[ -z "$EMAIL" ]]; then
  [[ -t 0 ]] || exit 2

  echo "🖼 Gravatar avatar"
  if [[ -n "$GIT_EMAIL" ]]; then
    read -rp "Use Git email ($GIT_EMAIL)? [Y/n]: " reply
    [[ ! "$reply" =~ ^[nN]$ ]] && EMAIL="$GIT_EMAIL"
  fi

  while [[ -z "$EMAIL" ]]; do
    read -rp "📧 Gravatar email: " EMAIL
    [[ "$EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] || EMAIL=""
  done

  echo "gravatar_email=\"$EMAIL\"" >"$GRAVATAR_CONFIG"
fi

# --------------------------------------------------
# Download avatar
# --------------------------------------------------
HASH="$(printf '%s' "$EMAIL" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1)"
curl -fsSL "https://www.gravatar.com/avatar/$HASH?s=$SIZE&d=identicon" \
  -o "$FACE_IMAGE"

# --------------------------------------------------
# GNOME session avatar (user scope)
# --------------------------------------------------
if command -v gsettings >/dev/null; then
  gsettings set org.gnome.desktop.account-service account-picture "$FACE_IMAGE" || true
fi

# --------------------------------------------------
# GDM avatar (system scope)
# --------------------------------------------------
ensure_sudo

install -m 644 "$FACE_IMAGE" "$ICON_DIR/$REAL_USER"

cat >"$USER_FILE" <<EOF
[User]
Icon=$ICON_DIR/$REAL_USER
EOF

systemctl restart accounts-daemon

log "✅ GDM avatar installed"
