#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="chrome"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

REPO_FILE="/etc/yum.repos.d/google-chrome.repo"

# === OS Check (Fedora only) ===============================================
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "Error: Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "Error: This script supports Fedora/RHEL-based systems only."
  exit 1
fi

# Google only publishes Chrome for Linux on x86_64 — skip cleanly elsewhere
# (exit 0 so setup continues). clean does not call this, so a previous
# install can still be removed.
require_x86_64() {
  if [[ "$(uname -m)" != "x86_64" ]]; then
    warn "Google Chrome is only published for x86_64 (this is $(uname -m)) — skipping"
    exit 0
  fi
}

# === Actions ==============================================================

deps() {
  require_x86_64
  log "Installing dependencies…"
  dnf_ensure ca-certificates curl dnf-plugins-core
}

install_repo() {
  require_x86_64
  log "Adding Google Chrome DNF repository (official .repo)…"

  if [[ ! -f "$REPO_FILE" ]]; then
    # Fedora-correct way: repo file owns GPG via https gpgkey=
    sudo dnf config-manager addrepo \
      --from-repofile=https://dl.google.com/linux/chrome/rpm/stable/x86_64/google-chrome.repo
  else
    log "Chrome repo already present."
  fi
}

remove_repo() {
  log "Removing Google Chrome repository…"
  sudo rm -f "$REPO_FILE"
}

install_pkg() {
  log "Installing google-chrome-stable…"
  dnf_ensure google-chrome-stable
}

config() {
  require_x86_64
  log "Configuring desktop launcher (StartupNotify=false)…"

  SRC_DESKTOP="/usr/share/applications/google-chrome.desktop"
  DEST_DIR="$HOME_DIR/.local/share/applications"
  DEST_DESKTOP="$DEST_DIR/google-chrome.desktop"

  sudo -u "$REAL_USER" mkdir -p "$DEST_DIR"

  if [[ -f "$SRC_DESKTOP" ]]; then
    sudo -u "$REAL_USER" cp -f "$SRC_DESKTOP" "$DEST_DESKTOP"
  else
    run_as_user tee "$DEST_DESKTOP" >/dev/null <<'EOF'
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

  local dest_dir="$HOME_DIR/.local/share/applications"
  if [[ -f "$dest_dir/google-chrome.desktop" ]]; then
    run_as_user rm -f "$dest_dir/google-chrome.desktop"
    run_as_user update-desktop-database "$dest_dir" >/dev/null 2>&1 || true
    log "Removed desktop override $dest_dir/google-chrome.desktop"
  fi
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
