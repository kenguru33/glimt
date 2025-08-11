#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES="$SCRIPT_DIR"
MODULE_NAME="user-profile"
CONFIG_DIR="$HOME/.config/glimt"
CONFIG_FILE="$CONFIG_DIR/userinfo.config"
ACTION="${1:-all}"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# === Dependencies ===
DEPS=("gum")

install_dependencies() {
  echo "🔧 Checking required dependencies..."

  if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
    for dep in "${DEPS[@]}"; do
      if ! command -v "$dep" &>/dev/null; then
        echo "📦 Installing $dep..."
        sudo apt install -y "$dep"
      else
        echo "✅ $dep is already installed."
      fi
    done

  elif [[ "$ID" == "fedora" ]]; then
    for dep in "${DEPS[@]}"; do
      if ! command -v "$dep" &>/dev/null; then
        echo "📦 Installing $dep..."
        sudo dnf install -y "$dep"
      else
        echo "✅ $dep is already installed."
      fi
    done

  else
    echo "❌ Unsupported OS: $ID"
    exit 1
  fi
}

ask_user_profile() {
  [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
  fallback_name="${name:-}"
  fallback_email="${email:-}"

  while true; do
    gum format --theme=dark <<EOF
# 👤 Let's personalize your setup

This information will be used for:

- ✅ Git configuration  
- 🖼️  Gravatar profile image
EOF

    while true; do
      USER_NAME=$(gum input \
        --prompt "📝 Full name: " \
        --placeholder "Bernt Anker" \
        --value "$fallback_name" \
        --width 50)

      if [[ -z "$USER_NAME" ]]; then
        gum style --foreground 1 "❌ Name cannot be empty."
      else
        break
      fi
    done

    while true; do
      USER_EMAIL=$(gum input \
        --prompt "📧 Email address: " \
        --placeholder "bernt@example.com" \
        --value "$fallback_email" \
        --width 50)

      if [[ -z "$USER_EMAIL" ]]; then
        gum style --foreground 1 "❌ Email cannot be empty."
      elif [[ "$USER_EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        break
      else
        gum style --foreground 1 "❌ Invalid email format. Please try again."
      fi
    done

    gum format --theme=dark <<<"# Review your info

✅ Name: $USER_NAME  
✅ Email: $USER_EMAIL"

    if gum confirm "💾 Save this information?"; then
      mkdir -p "$CONFIG_DIR"
      cat > "$CONFIG_FILE" <<EOF
name="$USER_NAME"
email="$USER_EMAIL"
EOF
      gum style --foreground 2 "✅ Saved user info to $CONFIG_FILE"
      break
    else
      gum style --foreground 3 "🔁 Let's try again..."
      clear
      if [[ -x "$MODULES/banner.sh" ]]; then
        "$MODULES/banner.sh"
      else
        gum style --foreground 1 "❌ Unable to find or execute the banner script at $MODULES/banner.sh"
      fi
    fi
  done
}

install_user_profile() {
  ask_user_profile
}

config_user_profile() {
  ask_user_profile
}

clean_user_profile() {
  rm -f "$CONFIG_FILE"
  gum style --foreground 1 "🗑️ Removed $CONFIG_FILE"
}

# === Entry Point ===
case "$ACTION" in
  all)
    install_dependencies
    install_user_profile
    ;;
  deps)
    install_dependencies
    ;;
  install)
    install_user_profile
    ;;
  config)
    config_user_profile
    ;;
  clean)
    clean_user_profile
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
