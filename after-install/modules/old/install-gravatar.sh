#!/bin/bash
set -e

MODULE_NAME="set-user-avatar"
FACE_IMAGE="$HOME/.face"
AFTER_INSTALL_CONFIG="$HOME/.config/glimt/userinfo.config"
MODULE_EMAIL_FILE="$HOME/.config/$MODULE_NAME/email"
GDM_ICON_DIR="/var/lib/AccountsService/icons"
DEFAULT_SIZE=256

ACTION="${1:-all}"
EMAIL="${2:-}"
SIZE="${3:-$DEFAULT_SIZE}"

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# === Dependencies ===
DEPS=("curl")

install_dependencies() {
  echo "🔧 Installing required dependencies..."

  if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
    sudo apt update
    for dep in "${DEPS[@]}"; do
      if ! dpkg -l | grep -qw "$dep"; then
        echo "📦 Installing $dep..."
        sudo apt install -y "$dep"
      else
        echo "✅ $dep is already installed."
      fi
    done
  elif [[ "$ID" == "fedora" ]]; then
    for dep in "${DEPS[@]}"; do
      if ! rpm -q "$dep" >/dev/null 2>&1; then
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

find_email() {
  if [[ -n "$EMAIL" ]]; then
    return
  fi

  if [[ -f "$AFTER_INSTALL_CONFIG" ]]; then
    EMAIL=$(grep -i '^email=' "$AFTER_INSTALL_CONFIG" | cut -d= -f2 | xargs)
    if [[ -n "$EMAIL" ]]; then
      echo "📄 Loaded email from $AFTER_INSTALL_CONFIG: $EMAIL"
      return
    fi
  fi

  if [[ -f "$MODULE_EMAIL_FILE" ]]; then
    EMAIL=$(<"$MODULE_EMAIL_FILE")
    echo "📄 Loaded email from $MODULE_EMAIL_FILE: $EMAIL"
    return
  fi

  echo "❌ No email provided and no config found."
  echo "💡 Please run: ./user-profile.sh"
  exit 1
}

install() {
  echo "📦 No-op install step. Nothing to do here for now."
}

config() {
  find_email

  mkdir -p "$(dirname "$MODULE_EMAIL_FILE")"
  echo "$EMAIL" > "$MODULE_EMAIL_FILE"

  HASH=$(echo -n "$EMAIL" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1)
  GRAVATAR_URL="https://www.gravatar.com/avatar/$HASH?s=$SIZE&d=identicon"

  echo "⬇️ Downloading Gravatar from: $GRAVATAR_URL"
  curl -sL "$GRAVATAR_URL" -o "$FACE_IMAGE"
  echo "🖼️ Saved avatar to $FACE_IMAGE"

  # Set GNOME avatar using gsettings if available
  if command -v gsettings &>/dev/null; then
    echo "🔧 Setting GNOME account picture via gsettings..."
    gsettings set org.gnome.desktop.account-service account-picture "$FACE_IMAGE" 2>/dev/null || true
  fi

  # Copy to GDM location
  echo "🔧 Setting GDM login avatar..."
  sudo mkdir -p "$GDM_ICON_DIR"
  sudo cp "$FACE_IMAGE" "$GDM_ICON_DIR/$(whoami)"

  # AccountsService config
  ACCOUNTS_USER_CONFIG="/var/lib/AccountsService/users/$(whoami)"
  sudo mkdir -p "$(dirname "$ACCOUNTS_USER_CONFIG")"
  sudo tee "$ACCOUNTS_USER_CONFIG" > /dev/null <<EOF
[User]
Icon=$GDM_ICON_DIR/$(whoami)
EOF

  echo "✅ GNOME and GDM avatar updated."
}

clean() {
  echo "🧹 Removing avatar and email config..."
  rm -f "$FACE_IMAGE"
  rm -f "$MODULE_EMAIL_FILE"
  echo "✅ Clean complete."
}

all() {
  install_dependencies
  config
}

# === Entry Point ===
case "$ACTION" in
  all)
    all
    ;;
  deps)
    install_dependencies
    ;;
  install)
    install
    ;;
  config)
    config
    ;;
  clean)
    clean
    ;;
  *)
    echo "Usage: $0 {all|deps|install|config|clean} [email] [size]"
    exit 1
    ;;
esac
