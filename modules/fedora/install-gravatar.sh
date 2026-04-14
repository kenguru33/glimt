#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Avatar setup failed. Exiting." >&2' ERR

MODULE_NAME="set-user-avatar"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME_DIR/.config/glimt"
CONFIG_FILE="$CONFIG_DIR/set-user-avatar.config"
FACE_IMAGE="$HOME_DIR/.face"
GDM_ICON_DIR="/var/lib/AccountsService/icons"
DEFAULT_SIZE=256
SIZE="${2:-$DEFAULT_SIZE}"
EMAIL=""

# === Ensure Fedora ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
    echo "❌ This script is for Fedora/RHEL-based systems only."
    exit 1
  fi
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# === Dependencies ===
install_dependencies() {
  echo "📦 Installing dependencies..."
  sudo dnf install -y curl
  # Check if gum is available, install if not
  if ! command -v gum &>/dev/null; then
    if sudo dnf install -y gum 2>/dev/null; then
      echo "✅ Installed gum"
    else
      echo "⚠️  gum not available in repos, will use basic prompts"
    fi
  fi
}

# === Prompt user for email ===
prompt_user_email() {
  if command -v gum &>/dev/null; then
    gum format --theme=dark <<EOF
# 🖼️ Set your GNOME/GDM Avatar

This will fetch your Gravatar image using the email address you provide.
EOF

    while true; do
      EMAIL=$(gum input --prompt "📧 Email address: " --placeholder "user@example.com" --width 50)
      if [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
      else
        gum style --foreground 1 "❌ Invalid email format. Please try again."
      fi
    done
  else
    echo "🖼️ Set your GNOME/GDM Avatar"
    echo "This will fetch your Gravatar image using the email address you provide."
    while true; do
      read -rp "📧 Email address: " EMAIL
      if [[ "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
      else
        echo "❌ Invalid email format. Please try again."
      fi
    done
  fi

  sudo -u "$REAL_USER" mkdir -p "$CONFIG_DIR"
  echo "gravatar_email=\"$EMAIL\"" | sudo -u "$REAL_USER" tee "$CONFIG_FILE" > /dev/null
  echo "✅ Saved to $CONFIG_FILE"
}

# === Load email from config, or prompt ===
load_email() {
  if [[ "$ACTION" == "reconfigure" ]]; then
    prompt_user_email
  elif [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
    if [[ -n "$gravatar_email" ]]; then
      EMAIL="$gravatar_email"
    fi
    if [[ -z "$EMAIL" ]]; then
      prompt_user_email
    fi
  else
    prompt_user_email
  fi
}

# === Set avatar ===
config_avatar() {
  load_email

  HASH=$(echo -n "$EMAIL" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1)
  GRAVATAR_URL="https://www.gravatar.com/avatar/$HASH?s=$SIZE&d=identicon"

  echo "⬇️  Downloading Gravatar from: $GRAVATAR_URL"
  sudo -u "$REAL_USER" curl -sL "$GRAVATAR_URL" -o "$FACE_IMAGE"
  chown "$REAL_USER:$REAL_USER" "$FACE_IMAGE"
  echo "🖼️  Saved avatar to $FACE_IMAGE"

  # GNOME user picture
  if command -v gsettings &>/dev/null; then
    echo "🔧 Setting GNOME account picture..."
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.account-service account-picture "$FACE_IMAGE" 2>/dev/null || true
  fi

  # GDM login avatar
  echo "🔧 Setting GDM login avatar..."
  sudo mkdir -p "$GDM_ICON_DIR"
  sudo cp "$FACE_IMAGE" "$GDM_ICON_DIR/$REAL_USER"
  sudo chmod 644 "$GDM_ICON_DIR/$REAL_USER"

  # AccountsService config
  ACCOUNTS_USER_CONFIG="/var/lib/AccountsService/users/$REAL_USER"
  sudo mkdir -p "$(dirname "$ACCOUNTS_USER_CONFIG")"
  sudo tee "$ACCOUNTS_USER_CONFIG" >/dev/null <<EOF
[User]
Icon=$GDM_ICON_DIR/$REAL_USER
EOF

  echo "✅ GNOME and GDM avatar updated."
}

# === Clean avatar ===
clean_avatar() {
  echo "🧹 Removing avatar and config..."
  sudo -u "$REAL_USER" rm -f "$FACE_IMAGE"
  sudo -u "$REAL_USER" rm -f "$CONFIG_FILE"
  sudo rm -f "$GDM_ICON_DIR/$REAL_USER"
  sudo rm -f "/var/lib/AccountsService/users/$REAL_USER"
  echo "✅ Avatar and config cleaned."
}

# === Entry Point ===
case "$ACTION" in
  all)
    install_dependencies
    config_avatar
    ;;
  deps)
    install_dependencies
    ;;
  install)
    echo "📦 No-op install step."
    ;;
  config)
    config_avatar
    ;;
  clean)
    clean_avatar
    ;;
  reconfigure)
    ACTION="reconfigure"
    config_avatar
    ;;
  *)
    echo "Usage: $0 {all|deps|install|config|clean|reconfigure} [size]"
    exit 1
    ;;
esac

