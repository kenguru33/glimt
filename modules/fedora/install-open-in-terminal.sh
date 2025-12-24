#!/bin/bash
set -euo pipefail
trap 'echo "❌ ${BASH_COMMAND} failed (line $LINENO)"; exit 1' ERR

ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
REPO_URL="https://github.com/Stunkymonkey/nautilus-open-any-terminal.git"
SRC_DIR="$HOME_DIR/.cache/nautilus-open-any-terminal"
EXT_FILE="$HOME_DIR/.local/share/nautilus-python/extensions/nautilus_open_any_terminal.py"

# --- Fedora check ---
if [[ -f /etc/os-release ]]; then . /etc/os-release; else
  echo "❌ Cannot detect OS"
  exit 1
fi
[[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || {
  echo "❌ Fedora/RHEL-based systems only."
  exit 1
}

deps() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y python3-nautilus gtk4 glib2 make gettext git
}

remove_system_entry() {
  if rpm -q nautilus-extension-gnome-terminal >/dev/null 2>&1; then
    echo "🗑 Removing system GNOME 'Open in Terminal'..."
    sudo dnf remove -y nautilus-extension-gnome-terminal
  fi
}

install_ext() {
  echo "⬇️  Fetching source..."
  sudo -u "$REAL_USER" rm -rf "$SRC_DIR"
  sudo -u "$REAL_USER" git clone --depth=1 "$REPO_URL" "$SRC_DIR"

  echo "🛠 Installing userspace extension..."
  pushd "$SRC_DIR" >/dev/null
  sudo -u "$REAL_USER" make
  sudo -u "$REAL_USER" make install-nautilus schema
  sudo -u "$REAL_USER" glib-compile-schemas "$HOME_DIR/.local/share/glib-2.0/schemas"
  popd >/dev/null
}

configure() {
  # Prefer BlackBox, else fall back
  if command -v blackbox-terminal >/dev/null 2>&1; then
    SELECTED="blackbox-terminal"
  elif command -v blackbox >/dev/null 2>&1; then
    SELECTED="blackbox"
  elif command -v kgx >/dev/null 2>&1; then
    SELECTED="kgx"
  elif command -v kitty >/dev/null 2>&1; then
    SELECTED="kitty"
  else
    SELECTED="gnome-terminal"
  fi

  echo "⚙️  Setting preferred terminal: $SELECTED"
  sudo -u "$REAL_USER" gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal "$SELECTED"
  sudo -u "$REAL_USER" gsettings set com.github.stunkymonkey.nautilus-open-any-terminal new-tab true

  # Patch label to always say "Open in terminal"
  if [[ -f "$EXT_FILE" ]]; then
    sudo -u "$REAL_USER" cp -a "$EXT_FILE" "$EXT_FILE.bak"
    sudo -u "$REAL_USER" sed -i 's/Open in Terminal/Open in terminal/' "$EXT_FILE"
    echo "📝 Menu label set to: Open in terminal"
  else
    echo "⚠️ Extension file not found to patch label."
  fi
}

restart_nautilus() {
  echo "🔄 Restarting Nautilus..."
  sudo -u "$REAL_USER" nautilus -q || true
}

clean() {
  echo "🧹 Removing userspace extension..."
  sudo -u "$REAL_USER" rm -f "$EXT_FILE" "$EXT_FILE.bak"
  sudo -u "$REAL_USER" glib-compile-schemas "$HOME_DIR/.local/share/glib-2.0/schemas" || true
  restart_nautilus
}

case "$ACTION" in
deps) deps ;;
install)
  deps
  install_ext
  configure
  remove_system_entry
  restart_nautilus
  ;;
config)
  configure
  remove_system_entry
  restart_nautilus
  ;;
clean) clean ;;
all)
  deps
  install_ext
  configure
  remove_system_entry
  restart_nautilus
  ;;
*)
  echo "Usage: $0 [deps|install|config|clean|all]"
  exit 2
  ;;
esac

