#!/bin/bash
set -e
trap 'echo "❌ Avatar setup failed. Exiting." >&2' ERR

MODULE_NAME="set-user-avatar"
ACTION="${1:-all}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="${HOME:-$(eval echo "~$REAL_USER")}"
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
  echo "📦 Checking dependencies..."
  # curl should be installed via rpm-ostree (install-silverblue-prereq.sh)
  if ! command -v curl &>/dev/null; then
    echo "⚠️  curl not found. Please install it via rpm-ostree first:"
    echo "   sudo rpm-ostree install -y curl"
    echo "   Then reboot and run this script again."
    exit 1
  fi
  # Check if gum is available (optional, not required)
  if ! command -v gum &>/dev/null; then
    echo "ℹ️  gum not available, will use basic prompts"
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

  mkdir -p "$CONFIG_DIR"
  echo "gravatar_email=\"$EMAIL\"" > "$CONFIG_FILE"
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
  curl -sL "$GRAVATAR_URL" -o "$FACE_IMAGE"
  echo "🖼️  Saved avatar to $FACE_IMAGE"

  # GNOME user picture
  if command -v gsettings &>/dev/null; then
    echo "🔧 Setting GNOME account picture..."
    gsettings set org.gnome.desktop.account-service account-picture "$FACE_IMAGE" 2>/dev/null || true
  fi

  # GDM login avatar (skipped for Silverblue - requires sudo)
  # The GNOME avatar set above is sufficient for most use cases
  # To set GDM login avatar, run manually with sudo:
  #   sudo cp "$FACE_IMAGE" /var/lib/AccountsService/icons/$USER
  #   sudo tee /var/lib/AccountsService/users/$USER >/dev/null <<EOF
  #   [User]
  #   Icon=/var/lib/AccountsService/icons/$USER
  #   EOF
  echo "✅ GNOME avatar updated."
}

# === Clean avatar ===
clean_avatar() {
  echo "🧹 Removing avatar and config..."
  rm -f "$FACE_IMAGE"
  rm -f "$CONFIG_FILE"
  # Note: GDM system files are not removed (would require sudo)
  # To manually remove GDM avatar:
  #   sudo rm -f /var/lib/AccountsService/icons/$USER
  #   sudo rm -f /var/lib/AccountsService/users/$USER
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

