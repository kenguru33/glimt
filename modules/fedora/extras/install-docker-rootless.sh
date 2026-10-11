#!/usr/bin/env bash
# modules/fedora/extras/install-docker-rootless.sh
# Glimt module: Install Docker in ROOTLESS mode for Fedora
# Actions: all | deps | install | config | clean
# clean = FULL PURGE (Docker + GNOME extension)

set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="docker-rootless"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

# === Real user ============================================================
REAL_UID="$(id -u "$REAL_USER")"

# === Paths ================================================================
GLIMT_ROOT="${GLIMT_ROOT:-$HOME_DIR/.glimt}"

ZSH_SRC="${ZSH_SRC:-$GLIMT_ROOT/modules/fedora/config/docker-rootless.zsh}"
ZSH_DIR="$HOME_DIR/.zsh/config"
ZSH_TARGET="$ZSH_DIR/docker-rootless.zsh"

GNOME_EXT_REPO="https://github.com/kenguru33/rootless-docker-gnome-extension.git"
GNOME_EXT_CACHE="$HOME_DIR/.cache/glimt-rootless-ext/repo"
GNOME_EXT_INSTALL_DIR="$HOME_DIR/.local/share/gnome-shell/extensions"

# ---- Fedora-only guard ----
fedora_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "${ID:-}" == "fedora" || "${ID_LIKE:-}" == *"fedora"* || "${ID:-}" == "rhel" ]] || die "Fedora/RHEL-only module."
  else
    die "Cannot detect OS."
  fi
}

# === Rootless env =========================================================
USER_RUNTIME_DIR="/run/user/$REAL_UID"
USER_DOCKER_HOST="unix://$USER_RUNTIME_DIR/docker.sock"
USER_BUS="unix:path=$USER_RUNTIME_DIR/bus"
export XDG_RUNTIME_DIR="$USER_RUNTIME_DIR"
export DOCKER_HOST="$USER_DOCKER_HOST"

# Run a command as $REAL_USER with the session environment that
# `systemctl --user`, docker and gnome-extensions need. Plain `sudo -u` resets
# the environment, so XDG_RUNTIME_DIR / DBUS_SESSION_BUS_ADDRESS would be lost.
as_user_session() {
  if [[ $EUID -ne 0 && "$(id -un)" == "$REAL_USER" ]]; then
    env XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" DOCKER_HOST="$USER_DOCKER_HOST" "$@"
  else
    sudo -u "$REAL_USER" env XDG_RUNTIME_DIR="$USER_RUNTIME_DIR" DBUS_SESSION_BUS_ADDRESS="$USER_BUS" DOCKER_HOST="$USER_DOCKER_HOST" "$@"
  fi
}

user_systemctl() { as_user_session systemctl --user "$@"; }

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
CONFLICTING_PKGS=(docker docker-client docker-common docker-engine moby-engine)

remove_conflicts() {
  # `rpm -q a b c` only succeeds when ALL are installed, so check each one and
  # remove just those present (dnf5 errors on packages that aren't installed).
  local p installed=()
  for p in "${CONFLICTING_PKGS[@]}"; do
    rpm -q "$p" >/dev/null 2>&1 && installed+=("$p")
  done
  ((${#installed[@]})) || return 0
  log "Removing conflicting Fedora docker packages: ${installed[*]}"
  sudo dnf remove -y "${installed[@]}" || true
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
# Reset the rootless daemon setup (systemd unit + setuptool state). Never
# touches ~/.local/share/docker — that holds the user's images, containers
# and volumes.
reset_rootless_setup() {
  as_user_session dockerd-rootless-setuptool.sh uninstall -f >/dev/null 2>&1 || true
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/systemd/user/docker.service" || true
  user_systemctl daemon-reload || true
}

# -------------------------------------------------------------------------
copy_zsh_config() {
  [[ -f "$ZSH_SRC" ]] || return 0
  deploy_config "$ZSH_SRC" "$ZSH_TARGET"
}

# -------------------------------------------------------------------------
start_once_then_stop() {
  user_systemctl daemon-reload
  user_systemctl start docker
  sleep 2
  as_user_session docker info >/dev/null
  user_systemctl stop docker
  user_systemctl disable docker
}

# ================= GNOME EXTENSION =======================================

detect_extension_uuid() {
  local md="" uuid=""
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

  (cd "$GNOME_EXT_CACHE" && sudo -u "$REAL_USER" chmod +x manage.sh && as_user_session ./manage.sh install)
}

uninstall_gnome_extension() {
  log "Uninstalling GNOME rootless Docker extension…"

  # Proper uninstall via manage.sh
  if [[ -f "$GNOME_EXT_CACHE/manage.sh" ]]; then
    (cd "$GNOME_EXT_CACHE" && as_user_session ./manage.sh uninstall || true)
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
# install: packages + rootless daemon setup. Config-type steps (env file, zsh
# config, smoke test, GNOME extension) live in config() so `all` runs each
# step exactly once.
install() {
  ensure_repo
  remove_conflicts

  log "Installing Docker CE rootless packages…"
  sudo dnf install -y docker-ce docker-ce-cli docker-ce-rootless-extras

  ensure_rootful_docker_off
  ensure_subids

  # Re-runs (glimt update) keep an existing setup; only a missing unit means
  # the rootless daemon still has to be (re)created.
  if [[ -f "$HOME_DIR/.config/systemd/user/docker.service" ]]; then
    log "Rootless Docker already set up — keeping it."
  else
    reset_rootless_setup
    as_user_session dockerd-rootless-setuptool.sh install
  fi
}

config() {
  write_user_env
  copy_zsh_config
  start_once_then_stop
  install_gnome_extension
}

clean() {
  log "FULL PURGE: removing Docker rootless + GNOME extension…"

  # Stop & remove rootless docker
  user_systemctl disable --now docker 2>/dev/null || true
  reset_rootless_setup
  if confirm "Also delete all Docker images, containers and volumes (~/.local/share/docker)?"; then
    sudo -u "$REAL_USER" rm -rf "$HOME_DIR/.local/share/docker" || true
  else
    log "Kept Docker data in ~/.local/share/docker."
  fi

  # Remove env + shell config
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/environment.d/docker-rootless.conf" || true
  sudo -u "$REAL_USER" rm -f "$ZSH_TARGET" || true

  # Remove GNOME extension
  uninstall_gnome_extension

  # Remove Docker packages
  sudo dnf remove -y docker-ce docker-ce-cli docker-ce-rootless-extras || true
  sudo rm -f /etc/yum.repos.d/docker-ce.repo

  # install masked the rootful units; undo that so a later rootful Docker works
  sudo systemctl unmask docker docker.socket 2>/dev/null || true

  log "Docker rootless and GNOME extension fully removed."
}

# -------------------------------------------------------------------------
fedora_guard

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
