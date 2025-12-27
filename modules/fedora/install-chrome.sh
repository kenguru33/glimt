#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="chrome"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

REPO_FILE="/etc/yum.repos.d/google-chrome.repo"

# === OS Check (Fedora only) ===============================================
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This script supports Fedora/RHEL-based systems only."
  exit 1
fi

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }

# === Actions ==============================================================

deps() {
  log "Installing dependencies…"
  sudo dnf makecache -y
  sudo dnf install -y ca-certificates curl dnf-plugins-core
}

install_repo() {
  log "Adding Google Chrome DNF repository (official .repo)…"

  if [[ ! -f "$REPO_FILE" ]]; then
    # Fedora-correct way: repo file owns GPG via https gpgkey=
    sudo dnf config-manager addrepo \
      --from-repofile=https://dl.google.com/linux/chrome/rpm/stable/x86_64/google-chrome.repo
  else
    log "Chrome repo already present."
  fi

  sudo dnf makecache -y
}

remove_repo() {
  log "Removing Google Chrome repository…"
  sudo rm -f "$REPO_FILE"
  sudo dnf makecache -y
}

install_pkg() {
  log "Installing google-chrome-stable…"
  sudo dnf install -y google-chrome-stable
}

config() {
  log "Configuring desktop launcher (StartupNotify=false)…"

  SRC_DESKTOP="/usr/share/applications/google-chrome.desktop"
  DEST_DIR="$HOME_DIR/.local/share/applications"
  DEST_DESKTOP="$DEST_DIR/google-chrome.desktop"

  sudo -u "$REAL_USER" mkdir -p "$DEST_DIR"

  if [[ -f "$SRC_DESKTOP" ]]; then
    sudo -u "$REAL_USER" cp -f "$SRC_DESKTOP" "$DEST_DESKTOP"
  else
    sudo -u "$REAL_USER" sh -c "cat >\"$DEST_DESKTOP\" <<'EOF'
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
EOF"
  fi

  if sudo -u "$REAL_USER" grep -q '^StartupNotify=' "$DEST_DESKTOP"; then
    sudo -u "$REAL_USER" sed -i 's/^StartupNotify=.*/StartupNotify=false/' "$DEST_DESKTOP"
  else
    sudo -u "$REAL_USER" sh -c "printf '\nStartupNotify=false\n' >> \"$DEST_DESKTOP\""
  fi

  chown "$REAL_USER:$REAL_USER" "$DEST_DESKTOP"
  chmod 0644 "$DEST_DESKTOP"

  sudo -u "$REAL_USER" update-desktop-database "$DEST_DIR" >/dev/null 2>&1 || true

  log "Desktop override written to $DEST_DESKTOP"
}

clean() {
  log "Removing Chrome and repository…"
  sudo dnf remove -y google-chrome-stable || true
  remove_repo || true
  log "Chrome removed."
}

all() {
  deps
  install_repo
  install_pkg
  config
  log "Done."
}

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
