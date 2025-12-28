#!/bin/bash
# modules/fedora/extras/install-docker-rootless.sh
# Glimt module: Install Docker in ROOTLESS mode for Fedora
# Actions: all | deps | install | config | clean
# clean = FULL PURGE (Docker + GNOME extension)

set -Eeuo pipefail
trap 'echo "❌ docker-rootless (fedora): error on line $LINENO" >&2' ERR

MODULE_NAME="docker-rootless"
ACTION="${1:-all}"

# === Real user ============================================================
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
REAL_UID="$(id -u "$REAL_USER")"

# === Paths ================================================================
GLIMT_ROOT="${GLIMT_ROOT:-$HOME_DIR/.glimt}"

ZSH_SRC="${ZSH_SRC:-$GLIMT_ROOT/modules/fedora/config/docker-rootless.zsh}"
ZSH_DIR="$HOME_DIR/.zsh/config"
ZSH_TARGET="$ZSH_DIR/docker-rootless.zsh"

GNOME_EXT_REPO="https://github.com/kenguru33/rootless-docker-gnome-extension.git"
GNOME_EXT_CACHE="$HOME_DIR/.cache/glimt-rootless-ext/repo"
GNOME_EXT_INSTALL_DIR="$HOME_DIR/.local/share/gnome-shell/extensions"

# === Fedora guard =========================================================
. /etc/os-release
[[ "$ID" == "fedora" || "$ID_LIKE" == *fedora* ]] || {
  echo "❌ Fedora only."
  exit 1
}

# === Rootless env =========================================================
export XDG_RUNTIME_DIR="/run/user/$REAL_UID"
export DOCKER_HOST="unix:///run/user/$REAL_UID/docker.sock"

log() { echo "🐳 $*"; }

# -------------------------------------------------------------------------
deps() {
  log "Installing prerequisites…"
  sudo dnf install -y \
    dbus-daemon \
    slirp4netns \
    fuse-overlayfs \
    curl \
    git \
    jq

  if ! command -v newuidmap >/dev/null 2>&1; then
    sudo dnf install -y shadow-utils-subid
  fi
}

# -------------------------------------------------------------------------
ensure_repo() {
  log "Ensuring Docker CE repository (DNF5-safe)…"
  if [[ ! -f /etc/yum.repos.d/docker-ce.repo ]]; then
    sudo curl -fsSL \
      https://download.docker.com/linux/fedora/docker-ce.repo \
      -o /etc/yum.repos.d/docker-ce.repo
  fi
}

# -------------------------------------------------------------------------
remove_conflicts() {
  if rpm -q docker docker-client docker-common docker-engine >/dev/null 2>&1; then
    log "Removing conflicting Fedora docker packages…"
    sudo dnf remove -y docker docker-client docker-common docker-engine || true
  fi
}

# -------------------------------------------------------------------------
ensure_subids() {
  if ! grep -q "^$REAL_USER:" /etc/subuid || ! grep -q "^$REAL_USER:" /etc/subgid; then
    log "Adding subuid/subgid ranges for $REAL_USER…"
    sudo usermod --add-subuids 100000-165536 "$REAL_USER"
    sudo usermod --add-subgids 100000-165536 "$REAL_USER"
  fi
}

# -------------------------------------------------------------------------
ensure_rootful_docker_off() {
  log "Disabling rootful Docker…"
  sudo systemctl stop docker docker.socket 2>/dev/null || true
  sudo systemctl disable docker docker.socket 2>/dev/null || true
  sudo systemctl mask docker docker.socket 2>/dev/null || true
  sudo rm -f /var/run/docker.sock 2>/dev/null || true
}

# -------------------------------------------------------------------------
write_user_env() {
  sudo -u "$REAL_USER" mkdir -p "$HOME_DIR/.config/environment.d"
  sudo -u "$REAL_USER" tee "$HOME_DIR/.config/environment.d/docker-rootless.conf" >/dev/null <<EOF
XDG_RUNTIME_DIR=/run/user/$REAL_UID
DOCKER_HOST=unix:///run/user/$REAL_UID/docker.sock
EOF
}

# -------------------------------------------------------------------------
cleanup_half_installed() {
  sudo -u "$REAL_USER" dockerd-rootless-setuptool.sh uninstall -f >/dev/null 2>&1 || true
  sudo -u "$REAL_USER" rm -rf "$HOME_DIR/.local/share/docker" || true
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/systemd/user/docker.service" || true
  sudo -u "$REAL_USER" systemctl --user daemon-reload || true
}

# -------------------------------------------------------------------------
copy_zsh_config() {
  [[ -f "$ZSH_SRC" ]] || return 0
  sudo -u "$REAL_USER" mkdir -p "$ZSH_DIR"
  sudo -u "$REAL_USER" cp -f "$ZSH_SRC" "$ZSH_TARGET"
}

# -------------------------------------------------------------------------
start_once_then_stop() {
  sudo -u "$REAL_USER" systemctl --user daemon-reload
  sudo -u "$REAL_USER" systemctl --user start docker
  sleep 2
  sudo -u "$REAL_USER" docker info >/dev/null
  sudo -u "$REAL_USER" systemctl --user stop docker
  sudo -u "$REAL_USER" systemctl --user disable docker
}

# ================= GNOME EXTENSION =======================================

detect_extension_uuid() {
  local md uuid
  md="$(find "$GNOME_EXT_CACHE" -name metadata.json | head -n1 || true)"
  if [[ -f "$md" ]]; then
    uuid="$(jq -r '.uuid // empty' "$md")"
  fi
  [[ -n "$uuid" ]] && echo "$uuid"
}

install_gnome_extension() {
  log "Installing GNOME rootless Docker extension…"
  sudo -u "$REAL_USER" mkdir -p "$(dirname "$GNOME_EXT_CACHE")"

  if [[ -d "$GNOME_EXT_CACHE/.git" ]]; then
    sudo -u "$REAL_USER" git -C "$GNOME_EXT_CACHE" pull --ff-only || true
  else
    sudo -u "$REAL_USER" git clone --depth 1 "$GNOME_EXT_REPO" "$GNOME_EXT_CACHE"
  fi

  (cd "$GNOME_EXT_CACHE" && sudo -u "$REAL_USER" chmod +x manage.sh && sudo -u "$REAL_USER" ./manage.sh install)
}

uninstall_gnome_extension() {
  log "Uninstalling GNOME rootless Docker extension…"

  # Proper uninstall via manage.sh
  if [[ -f "$GNOME_EXT_CACHE/manage.sh" ]]; then
    (cd "$GNOME_EXT_CACHE" && sudo -u "$REAL_USER" ./manage.sh uninstall || true)
  fi

  # Remove installed extension directories
  local uuid
  uuid="$(detect_extension_uuid || true)"
  if [[ -n "$uuid" ]]; then
    sudo -u "$REAL_USER" rm -rf "$GNOME_EXT_INSTALL_DIR/$uuid" || true
  fi

  sudo -u "$REAL_USER" rm -rf "$GNOME_EXT_CACHE" || true
}

# -------------------------------------------------------------------------
install() {
  deps
  ensure_repo
  remove_conflicts

  log "Installing Docker CE rootless packages…"
  sudo dnf install -y docker-ce docker-ce-cli docker-ce-rootless-extras

  ensure_rootful_docker_off
  ensure_subids
  write_user_env
  cleanup_half_installed

  sudo -u "$REAL_USER" dockerd-rootless-setuptool.sh install

  copy_zsh_config
  start_once_then_stop
  install_gnome_extension
}

config() {
  write_user_env
  ensure_rootful_docker_off
  copy_zsh_config
  start_once_then_stop
  install_gnome_extension
}

clean() {
  log "FULL PURGE: removing Docker rootless + GNOME extension…"

  # Stop & remove rootless docker
  sudo -u "$REAL_USER" systemctl --user disable --now docker 2>/dev/null || true
  cleanup_half_installed

  # Remove env + shell config
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/environment.d/docker-rootless.conf" || true
  sudo -u "$REAL_USER" rm -f "$ZSH_TARGET" || true

  # Remove GNOME extension
  uninstall_gnome_extension

  # Remove Docker packages
  sudo dnf remove -y docker-ce docker-ce-cli docker-ce-rootless-extras || true
  sudo dnf autoremove -y || true

  log "Docker rootless and GNOME extension fully removed."
}

# -------------------------------------------------------------------------
case "$ACTION" in
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
all)
  deps
  install
  config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac
