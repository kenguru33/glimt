#!/bin/bash
set -e
trap 'echo "❌ An error occurred. Exiting." >&2' ERR

MODULE_NAME="add-local-bin-path"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
ZSHRC="$HOME_DIR/.zshrc"
LOCAL_BIN="$HOME_DIR/.local/bin"

# === Step: install ===
install() {
  echo "📁 Ensuring $LOCAL_BIN exists..."
  mkdir -p "$LOCAL_BIN"
  chown "$REAL_USER:$REAL_USER" "$LOCAL_BIN"
  echo "✅ $LOCAL_BIN directory is ready."
}

# === Step: config ===
config() {
  if ! grep -qs 'export PATH=.*\.local/bin' "$ZSHRC"; then
    echo "🔧 Adding $LOCAL_BIN to PATH in $ZSHRC"
    echo '' >> "$ZSHRC"
    echo '# Add local bin to PATH' >> "$ZSHRC"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$ZSHRC"
  else
    echo "✅ PATH already includes ~/.local/bin in $ZSHRC"
  fi
}

# === Step: clean ===
clean() {
  echo "🧹 Removing local bin PATH entry from $ZSHRC if present..."
  sed -i '/# Add local bin to PATH/d' "$ZSHRC"
  sed -i '/export PATH="\$HOME\/.local\/bin:\$PATH"/d' "$ZSHRC"
  echo "✅ Cleaned up $ZSHRC"
}

# === Entry point ===
case "$ACTION" in
  install)
    install
    ;;
  config)
    config
    ;;
  clean)
    clean
    ;;
  all)
    install
    config
    ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [install|config|clean|all]"
    exit 1
    ;;
esac
