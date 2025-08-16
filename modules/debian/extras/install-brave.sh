#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="brave"
ACTION="${1:-all}"

KEYRING="/etc/apt/keyrings/brave-browser.gpg"
LISTFILE="/etc/apt/sources.list.d/brave-browser-release.list"

require_sudo() {
  if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo -E -- "$0" "$ACTION"
  fi
}

is_debian() {
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]
}

deps() {
  echo "🔧 [$MODULE_NAME] Installing dependencies…"
  apt-get update -y
  apt-get install -y apt-transport-https curl gnupg
  install -d -m 0755 /etc/apt/keyrings
}

install_repo() {
  echo "➕ [$MODULE_NAME] Adding Brave APT repo…"
  if [[ ! -f "$KEYRING" ]]; then
    curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
      -o "$KEYRING"
    chmod 0644 "$KEYRING"
  fi

  echo "deb [arch=amd64 signed-by=$KEYRING] https://brave-browser-apt-release.s3.brave.com/ stable main" \
    >"$LISTFILE"
  chmod 0644 "$LISTFILE"
}

remove_repo() {
  echo "➖ [$MODULE_NAME] Removing Brave APT repo…"
  rm -f "$LISTFILE" "$KEYRING"
}

install_pkg() {
  echo "📦 [$MODULE_NAME] Installing brave-browser…"
  apt-get update -y
  apt-get install -y brave-browser
}

config() {
  echo "⚙️  [$MODULE_NAME] Creating per-user launcher override (StartupNotify=false)…"

  # Resolve invoking user (not root) and home
  TARGET_USER="${SUDO_USER:-$USER}"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || {
    echo "❌ Could not resolve home for $TARGET_USER"; return 1; }

  SRC_DESKTOP="/usr/share/applications/brave-browser.desktop"
  DEST_DIR="$TARGET_HOME/.local/share/applications"
  DEST_DESKTOP="$DEST_DIR/brave-browser.desktop"

  install -d -m 0755 "$DEST_DIR"

  if [[ -f "$SRC_DESKTOP" ]]; then
    cp -f "$SRC_DESKTOP" "$DEST_DESKTOP"
  else
    # Fallback minimal launcher if system file isn't present yet
    cat >"$DEST_DESKTOP" <<'EOF'
[Desktop Entry]
Version=1.0
Name=Brave Browser
GenericName=Web Browser
Comment=Browse the Web
Exec=/usr/bin/brave-browser %U
Terminal=false
Icon=brave-browser
Type=Application
Categories=Network;WebBrowser;
StartupWMClass=brave-browser
EOF
  fi

  # Ensure StartupNotify=false (replace if present, else append)
  if grep -q '^StartupNotify=' "$DEST_DESKTOP"; then
    sed -i 's/^StartupNotify=.*/StartupNotify=false/' "$DEST_DESKTOP"
  else
    printf '\nStartupNotify=false\n' >> "$DEST_DESKTOP"
  fi

  chown "$TARGET_USER:$TARGET_USER" "$DEST_DESKTOP"
  chmod 0644 "$DEST_DESKTOP"

  # Refresh desktop database (ignore if missing)
  sudo -u "$TARGET_USER" update-desktop-database "$DEST_DIR" >/dev/null 2>&1 || true

  echo "✅ [$MODULE_NAME] Override saved at: $DEST_DESKTOP (StartupNotify=false)."
}

clean() {
  echo "🧹 [$MODULE_NAME] Purging Brave and repo…"
  apt-get purge -y brave-browser || true
  remove_repo || true
  apt-get update -y || true
  apt-get autoremove -y || true
}

all() {
  deps
  install_repo
  install_pkg
  config
  echo "✅ [$MODULE_NAME] Done."
}

main() {
  is_debian || { echo "❌ Debian-based systems only."; exit 1; }
  require_sudo
  case "$ACTION" in
    deps) deps ;;
    install) install_repo; install_pkg ;;
    config) config ;;
    clean) clean ;;
    all) all ;;
    *) echo "Usage: $0 [all|deps|install|config|clean]"; exit 2 ;;
  esac
}

main
