#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="chrome"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

ARCH="$(uname -m)"
KEYRING="/etc/pki/rpm-gpg/google-chrome.gpg"
REPO_FILE="/etc/yum.repos.d/google-chrome.repo"

# === OS Check (Fedora only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This script supports Fedora/RHEL-based systems only."
  exit 1
fi

deps() {
  echo "🔧 [$MODULE_NAME] Installing dependencies…"
  sudo dnf makecache -y
  sudo dnf install -y ca-certificates curl gnupg2 dnf-plugins-core
}

install_repo() {
  echo "➕ [$MODULE_NAME] Adding Google Chrome DNF repository…"

  # Import GPG key
  if [[ ! -f "$KEYRING" ]]; then
    sudo install -m0755 -d "$(dirname "$KEYRING")"
    curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | sudo gpg --dearmor -o "$KEYRING"
    sudo chmod a+r "$KEYRING"
  fi

  # Remove old repo file if it exists to avoid conflicts
  if [[ -f "$REPO_FILE" ]]; then
    echo "ℹ️ Removing existing Chrome repository file: $REPO_FILE"
    sudo rm -f "$REPO_FILE"
  fi

  # Determine architecture for repository URL
  case "$ARCH" in
    x86_64)
      REPO_ARCH="x86_64"
      ;;
    aarch64)
      REPO_ARCH="aarch64"
      ;;
    *)
      echo "❌ Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac

  # Add repository using dnf config-manager
  sudo dnf config-manager --add-repo "https://dl.google.com/linux/chrome/rpm/stable/$REPO_ARCH" || {
    # Fallback: create repo file manually
    sudo tee "$REPO_FILE" >/dev/null <<EOF
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/$REPO_ARCH
enabled=1
gpgcheck=1
gpgkey=file://$KEYRING
EOF
  }
  
  sudo dnf makecache -y
}

remove_repo() {
  echo "➖ [$MODULE_NAME] Removing Google Chrome DNF repository…"
  sudo rm -f "$REPO_FILE"
  sudo rm -f "$KEYRING"
  sudo dnf makecache -y
}

install_pkg() {
  echo "📦 [$MODULE_NAME] Installing google-chrome-stable…"
  sudo dnf install -y google-chrome-stable
}

config() {
  echo "⚙️  [$MODULE_NAME] Forcing instant dock icon (StartupNotify=false)…"

  SRC_DESKTOP="/usr/share/applications/google-chrome.desktop"
  DEST_DIR="$HOME_DIR/.local/share/applications"
  DEST_DESKTOP="$DEST_DIR/google-chrome.desktop"

  sudo -u "$REAL_USER" mkdir -p "$DEST_DIR"

  if [[ -f "$SRC_DESKTOP" ]]; then
    sudo -u "$REAL_USER" cp -f "$SRC_DESKTOP" "$DEST_DESKTOP"
  else
    # Fallback minimal launcher if the system one isn't there yet
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

  # Ensure StartupNotify=false (replace if present, append if missing)
  if sudo -u "$REAL_USER" grep -q '^StartupNotify=' "$DEST_DESKTOP"; then
    sudo -u "$REAL_USER" sed -i 's/^StartupNotify=.*/StartupNotify=false/' "$DEST_DESKTOP"
  else
    sudo -u "$REAL_USER" sh -c "printf '\nStartupNotify=false\n' >> \"$DEST_DESKTOP\""
  fi

  chown "$REAL_USER:$REAL_USER" "$DEST_DESKTOP"
  chmod 0644 "$DEST_DESKTOP"

  # Refresh desktop db for that user (ignore if tool missing)
  sudo -u "$REAL_USER" update-desktop-database "$DEST_DIR" >/dev/null 2>&1 || true

  echo "✅ [$MODULE_NAME] Created override at $DEST_DESKTOP with StartupNotify=false."
  echo "   Tip: If the change doesn't reflect immediately, re-open the app grid."
}

clean() {
  echo "🧹 [$MODULE_NAME] Removing Chrome and repository…"
  sudo dnf remove -y google-chrome-stable || true
  remove_repo || true
  echo "✅ Chrome removed."
}

all() {
  deps
  install_repo
  install_pkg
  config
  echo "✅ [$MODULE_NAME] Done."
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

