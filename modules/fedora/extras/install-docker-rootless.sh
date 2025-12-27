#!/usr/bin/env bash
# modules/fedora/extras/install-docker-rootless.sh
# Glimt module: Install Docker in ROOTLESS mode on Fedora.
# - Uses Docker's official .repo (NO manual GPG handling)
# - Disables rootful daemon/socket
# - Sets numeric UID env (XDG_RUNTIME_DIR / DOCKER_HOST)
# - Idempotent + self-healing
# - Copies Zsh snippet only (no rc edits)
# - Verifies rootless daemon by starting once, then stops & disables
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ docker-rootless: error on line $LINENO" >&2' ERR

MODULE_NAME="docker-rootless"
ACTION="${1:-all}"

# === Real user context ====================================================
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

# === Paths / Config ======================================================
GLIMT_ROOT="${GLIMT_ROOT:-$HOME_DIR/.glimt}"

ZSH_SRC="${ZSH_SRC:-$GLIMT_ROOT/modules/fedora/config/docker-rootless.zsh}"
ZSH_DIR="$HOME_DIR/.zsh/config"
ZSH_TARGET="$ZSH_DIR/docker-rootless.zsh"

REPO_FILE="/etc/yum.repos.d/docker-ce.repo"

# Rootless runtime env (exported for this run)
REAL_UID="$(sudo -u "$REAL_USER" id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$REAL_UID}"
export DOCKER_HOST="${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock}"

# === Fedora-only guard ====================================================
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || {
    echo "❌ Fedora/RHEL-based systems only."
    exit 1
  }
else
  echo "❌ Cannot detect OS."
  exit 1
fi

# --- Helpers --------------------------------------------------------------
log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }

log_recent_unit() {
  local unit="$1" lines="${2:-120}"
  echo "----- logs: $unit (last ${lines}) -----"
  sudo -u "$REAL_USER" journalctl --user -u "$unit" -n "$lines" --no-pager || true
  echo "-----------------------------------------------------------------"
}

# --- Actions --------------------------------------------------------------
deps() {
  log "Installing prerequisites…"
  sudo dnf makecache -y
  sudo dnf install -y \
    dnf-plugins-core \
    shadow-utils \
    slirp4netns \
    fuse-overlayfs \
    rsync \
    curl \
    gnupg2 \
    git || true
}

ensure_repo() {
  log "Ensuring Docker DNF repository (official .repo)…"
  if [[ ! -f "$REPO_FILE" ]]; then
    # Correct Fedora way: repo owns GPG via https gpgkey=
    sudo dnf config-manager addrepo \
      --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
  fi
  sudo dnf makecache -y
}

remove_conflicts() {
  if rpm -q docker >/dev/null 2>&1; then
    log "Removing conflicting package: docker"
    sudo dnf remove -y docker || true
  fi
}

ensure_rootful_off() {
  log "Disabling rootful Docker (service + socket)…"
  sudo systemctl stop docker.service docker.socket 2>/dev/null || true
  sudo systemctl disable docker.service docker.socket 2>/dev/null || true
  sudo systemctl mask docker.service docker.socket 2>/dev/null || true
  sudo rm -f /var/run/docker.sock 2>/dev/null || true
}

ensure_subids() {
  local need=0
  grep -q "^$REAL_USER:" /etc/subuid || need=1
  grep -q "^$REAL_USER:" /etc/subgid || need=1
  if [[ $need -eq 1 ]]; then
    log "Adding subuid/subgid ranges for $REAL_USER…"
    sudo usermod --add-subuids 100000-165536 "$REAL_USER"
    sudo usermod --add-subgids 100000-165536 "$REAL_USER"
    log "subuid/subgid updated (relogin may be required if start fails)."
  fi
}

write_user_env() {
  log "Writing numeric UID env for rootless Docker…"
  sudo -u "$REAL_USER" mkdir -p "$HOME_DIR/.config/environment.d"
  sudo -u "$REAL_USER" sh -c "cat >\"$HOME_DIR/.config/environment.d/docker-rootless.conf\" <<EOF
XDG_RUNTIME_DIR=/run/user/${REAL_UID}
DOCKER_HOST=unix:///run/user/${REAL_UID}/docker.sock
EOF"
}

apply_env_now() {
  export XDG_RUNTIME_DIR="/run/user/${REAL_UID}"
  export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
}

cleanup_half_installed() {
  log "Cleaning any half-installed rootless setup…"
  sudo -u "$REAL_USER" /usr/bin/dockerd-rootless-setuptool.sh uninstall -f >/dev/null 2>&1 || true
  sudo -u "$REAL_USER" rm -rf "$HOME_DIR/.local/share/docker" >/dev/null 2>&1 || true
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/systemd/user/docker.service" >/dev/null 2>&1 || true
  sudo -u "$REAL_USER" systemctl --user daemon-reload || true
}

verify_running() {
  if ! sudo -u "$REAL_USER" docker info >/dev/null 2>&1; then
    log "Cannot reach rootless Docker at ${DOCKER_HOST}"
    log_recent_unit "docker.service" 120
    return 1
  fi
  log "Rootless Docker is running at ${DOCKER_HOST}"
}

copy_zsh_config() {
  if [[ ! -f "$ZSH_SRC" ]]; then
    log "Zsh snippet not found at $ZSH_SRC (skipping)."
    return 0
  fi
  sudo -u "$REAL_USER" mkdir -p "$ZSH_DIR"
  sudo -u "$REAL_USER" cp -f "$ZSH_SRC" "$ZSH_TARGET"
  chown "$REAL_USER:$REAL_USER" "$ZSH_TARGET"
  log "Copied Zsh snippet → $ZSH_TARGET"
}

start_user_service_once() {
  log "Starting user docker.service (verify)…"
  sudo -u "$REAL_USER" systemctl --user daemon-reload || true
  if ! sudo -u "$REAL_USER" systemctl --user start docker; then
    log "Failed to start user docker.service"
    log_recent_unit "docker.service" 120
    return 1
  fi
  for _ in {1..10}; do
    sudo -u "$REAL_USER" docker info >/dev/null 2>&1 && break
    sleep 1
  done
  verify_running
  log "Stopping user docker.service (manual start next time)…"
  sudo -u "$REAL_USER" systemctl --user stop docker || true
  sudo -u "$REAL_USER" systemctl --user disable docker || true
  log "Start manually with: systemctl --user start docker"
}

install() {
  deps
  ensure_repo
  remove_conflicts

  log "Installing Docker engine + CLI + rootless extras…"
  sudo dnf install -y docker-ce docker-ce-cli docker-ce-rootless-extras

  ensure_rootful_off
  ensure_subids
  write_user_env
  apply_env_now

  sudo -u "$REAL_USER" systemctl --user daemon-reload || true

  log "Running rootless setup tool (idempotent)…"
  cleanup_half_installed
  if ! sudo -u "$REAL_USER" /usr/bin/dockerd-rootless-setuptool.sh install; then
    log "Rootless setup failed"
    log_recent_unit "docker.service" 120
    exit 1
  fi

  copy_zsh_config
  start_user_service_once
}

config() {
  write_user_env
  apply_env_now
  ensure_rootful_off
  copy_zsh_config
  start_user_service_once
}

clean() {
  log "Removing rootless user service and env (packages kept)…"
  sudo -u "$REAL_USER" systemctl --user disable --now docker 2>/dev/null || true
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/systemd/user/docker.service" 2>/dev/null || true
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/environment.d/docker-rootless.conf" 2>/dev/null || true
  sudo -u "$REAL_USER" systemctl --user daemon-reload || true

  log "Removing copied Zsh snippet…"
  sudo -u "$REAL_USER" rm -f "$ZSH_TARGET" 2>/dev/null || true

  log "Optional package removal:"
  echo "  sudo dnf remove -y docker-ce docker-ce-cli docker-ce-rootless-extras"
}

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
