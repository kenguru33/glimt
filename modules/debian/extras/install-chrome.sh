#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="chrome"
ACTION="${1:-all}"

KEYRING="/etc/apt/keyrings/google-chrome.gpg"
SOURCES="/etc/apt/sources.list.d/google-chrome.sources"
DEFAULTS="/etc/default/google-chrome"

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
  apt-get install -y ca-certificates curl gnupg
  install -d -m 0755 /etc/apt/keyrings
}

write_defaults() {
  # Hindrer at Google legger global nøkkel i trusted.gpg.d eller reaktiverer repo etter dist-upgrade
  mkdir -p "$(dirname "$DEFAULTS")"
  cat >"$DEFAULTS" <<'EOF'
repo_add_once=false
repo_reenable_on_distupgrade=false
EOF
  chmod 0644 "$DEFAULTS"
}

install_repo() {
  echo "➕ [$MODULE_NAME] Adding Google Chrome APT repo…"

  # (Re)last alltid nøkkelen for å sikre riktig subkey-sett
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub |
    gpg --dearmor -o "$KEYRING".tmp
  install -m 0644 "$KEYRING".tmp "$KEYRING"
  rm -f "$KEYRING".tmp

  # Bytt til .sources-format med Signed-By
  cat >"$SOURCES" <<EOF
Types: deb
URIs: https://dl.google.com/linux/chrome/deb
Suites: stable
Components: main
Architectures: amd64
Signed-By: $KEYRING
EOF
  chmod 0644 "$SOURCES"

  write_defaults
}

remove_repo() {
  echo "➖ [$MODULE_NAME] Removing Google Chrome APT repo…"
  rm -f "$SOURCES"
  rm -f "$KEYRING"
  rm -f "$DEFAULTS"
}

install_pkg() {
  echo "📦 [$MODULE_NAME] Installing google-chrome-stable…"
  apt-get update -y
  apt-get install -y google-chrome-stable
}

config() {
  echo "⚙️  [$MODULE_NAME] Forcing instant dock icon (StartupNotify=false)…"

  # Resolve the real user/home even when running with sudo
  TARGET_USER="${SUDO_USER:-$USER}"
  TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
  [[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] || {
    echo "❌ Could not resolve home for $TARGET_USER"; return 1; }

  SRC_DESKTOP="/usr/share/applications/google-chrome.desktop"
  DEST_DIR="$TARGET_HOME/.local/share/applications"
  DEST_DESKTOP="$DEST_DIR/google-chrome.desktop"

  install -d -m 0755 "$DEST_DIR"

  if [[ -f "$SRC_DESKTOP" ]]; then
    cp -f "$SRC_DESKTOP" "$DEST_DESKTOP"
  else
    # Fallback minimal launcher if the system one isn't there yet
    cat >"$DEST_DESKTOP" <<'EOF'
[Desktop Entry]
Version=1.0
Name=Google Chrome
GenericName=Web Browser
Comment=Access the Internet
Exec=/usr/bin/google-chrome-stable %U
Terminal=false
Icon=google-chrome
Type=Application
Categories=Network;WebBrowser;
StartupWMClass=Google-chrome
EOF
  fi

  # Ensure StartupNotify=false (replace if present, append if missing)
  if grep -q '^StartupNotify=' "$DEST_DESKTOP"; then
    sed -i 's/^StartupNotify=.*/StartupNotify=false/' "$DEST_DESKTOP"
  else
    printf '\nStartupNotify=false\n' >> "$DEST_DESKTOP"
  fi

  chown "$TARGET_USER:$TARGET_USER" "$DEST_DESKTOP"
  chmod 0644 "$DEST_DESKTOP"

  # Refresh desktop db for that user (ignore if tool missing)
  sudo -u "$TARGET_USER" update-desktop-database "$DEST_DIR" >/dev/null 2>&1 || true

  echo "✅ [$MODULE_NAME] Created override at $DEST_DESKTOP with StartupNotify=false."
  echo "   Tip: If the change doesn’t reflect immediately, re-open the app grid."
}


clean() {
  echo "🧹 [$MODULE_NAME] Purging Chrome and repo…"
  apt-get purge -y google-chrome-stable || true
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
  is_debian || {
    echo "❌ Debian-based systems only."
    exit 1
  }
  require_sudo
  case "$ACTION" in
  deps) deps ;;
  install)
    install_repo
    install_pkg
    ;;
  config) config ;;
  clean) clean ;;
  all) all ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 2
    ;;
  esac
}

main
