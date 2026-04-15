#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="1password"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

# === OS Detection ========================================================
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Unable to detect OS."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This script supports Fedora/RHEL-based systems only."
  exit 1
fi

# === Constants ===========================================================
FEDORA_REPO="/etc/yum.repos.d/1password.repo"
DESKTOP_OVERRIDE="$HOME_DIR/.local/share/applications/1password.desktop"
DEPS=(curl ca-certificates dnf-plugins-core)

# === Dependencies ========================================================
install_deps() {
  log "Installing dependencies…"
  sudo dnf install -y "${DEPS[@]}"
}

# === Repo ================================================================
install_repo() {
  log "Adding 1Password DNF repository…"

  if [[ ! -f "$FEDORA_REPO" ]]; then
    sudo tee "$FEDORA_REPO" >/dev/null <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
  else
    log "Repo already present."
  fi
}

remove_repo() {
  log "Removing 1Password repository…"
  sudo rm -f "$FEDORA_REPO"
}

# === Install =============================================================
install_1password() {
  log "Installing 1Password…"
  sudo dnf install -y 1password
  log "1Password installed."
}

# === Config ==============================================================
config_1password() {
  log "Verifying installation…"
  if command -v 1password >/dev/null 2>&1 || rpm -q 1password >/dev/null 2>&1; then
    log "1Password is installed and ready."
  else
    echo "❌ 1Password not found. Run install first."
    exit 1
  fi
  verify_binary 1password --version

  # 1Password (Electron) does not reliably detect the GNOME dark preference on
  # Wayland. Forcing GTK_THEME=Adwaita:dark makes Electron read a dark GTK theme
  # at startup, setting nativeTheme.shouldUseDarkColors=true so the app and its
  # window decorations render in dark mode.
  local desktop_src="/usr/share/applications/1password.desktop"
  if [[ -f "$desktop_src" ]]; then
    run_as_user mkdir -p "$(dirname "$DESKTOP_OVERRIDE")"
    local tmp
    tmp=$(mktemp)
    sed 's|^Exec=\(/[^ ]*\)|Exec=env GTK_THEME=Adwaita:dark \1|g' \
      "$desktop_src" > "$tmp"
    install -m 644 -o "$REAL_USER" "$tmp" "$DESKTOP_OVERRIDE"
    rm -f "$tmp"
    log "Applied dark-theme fix to 1Password desktop entry."
  else
    warn "System desktop file not found — skipping dark theme fix."
  fi
}

# === Clean ===============================================================
clean_1password() {
  log "Removing 1Password…"
  sudo dnf remove -y 1password || true
  remove_repo || true
  rm -f "$DESKTOP_OVERRIDE" || true
  log "1Password removed."
}

# === Dispatcher ==========================================================
case "$ACTION" in
deps)
  install_deps
  ;;
install)
  install_deps
  install_repo
  install_1password
  ;;
config)
  config_1password
  ;;
clean)
  clean_1password
  ;;
all)
  install_deps
  install_repo
  install_1password
  config_1password
  ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
