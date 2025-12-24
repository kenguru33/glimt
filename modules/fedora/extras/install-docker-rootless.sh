#!/bin/bash
# modules/fedora/extras/install-docker-rootless.sh
# Glimt module: Install Docker in ROOTLESS mode for the current user.
# - Installs engine (dockerd), CLI, and rootless extras from Docker's repo
# - Disables/masks the system daemon/socket (rootful) so rootless can run
# - Self-heals common failures (subuid/subgid, helpers, half-installs)
# - Writes env with *numeric* UID and applies it to the current shell
# - Zsh: ONLY copies modules/fedora/config/docker-rootless.zsh → ~/.zsh/config/docker-rootless.zsh
# - Verifies rootless daemon by starting it once, then stops & disables it
# - Installs GNOME extension by running the repo's own manage.sh and enables it
# - Pattern: all | deps | install | config | clean

set -euo pipefail
trap 'echo "❌ docker-rootless: error on line $LINENO" >&2' ERR

MODULE_NAME="docker-rootless"
ACTION="${1:-all}"

# === Real user context ====================================================
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

# === Config (override with env) ==========================================
GLIMT_ROOT="${GLIMT_ROOT:-$HOME_DIR/.glimt}"

# Zsh snippet copy (copy only; no edits to user rc files)
ZSH_SRC="${ZSH_SRC:-$GLIMT_ROOT/modules/fedora/config/docker-rootless.zsh}"
ZSH_DIR="${ZSH_DIR:-$HOME_DIR/.zsh/config}"
ZSH_TARGET="${ZSH_TARGET:-$ZSH_DIR/docker-rootless.zsh}"

# GNOME extension (use its own manage.sh)
GNOME_EXT_REPO="${GNOME_EXT_REPO:-https://github.com/kenguru33/rootless-docker-gnome-extension.git}"
GNOME_EXT_BRANCH="${GNOME_EXT_BRANCH:-main}"
GNOME_EXT_CACHE="${GNOME_EXT_CACHE:-$HOME_DIR/.cache/glimt-rootless-ext/repo}"

# === Fedora-only guard ====================================================
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || {
    echo "❌ Fedora/RHEL-based systems only."
    exit 1
  }
else
  echo "❌ Cannot detect OS."
  exit 1
fi

ARCH="$(uname -m)"
KEYRING="/etc/pki/rpm-gpg/docker.gpg"
REPO_FILE="/etc/yum.repos.d/docker-ce.repo"

# Rootless runtime env (will be overwritten by write_user_env/apply_env_now)
REAL_USER_UID="$(id -u "$REAL_USER" 2>/dev/null || id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$REAL_USER_UID}"
export DOCKER_HOST="${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock}"

# --- Helpers --------------------------------------------------------------

log_recent_unit() {
  local unit="$1" lines="${2:-80}"
  echo "----- logs: $unit (last ${lines}) -----"
  sudo -u "$REAL_USER" journalctl --user -u "$unit" -n "$lines" --no-pager || true
  echo "-----------------------------------------------------------------"
}

deps() {
  echo "📦 Installing prerequisites…"
  sudo dnf makecache -y
  sudo dnf install -y rsync shadow-utils dbus-user-session slirp4netns fuse-overlayfs curl gnupg2 dnf-plugins-core
  # For cloning/running the extension installer
  sudo dnf install -y git || true
}

ensure_repo() {
  echo "🏷️  Ensuring Docker DNF repository…"
  if [[ ! -f "$REPO_FILE" ]]; then
    # Import GPG key
    if [[ ! -f "$KEYRING" ]]; then
      sudo install -m0755 -d "$(dirname "$KEYRING")"
      curl -fsSL https://download.docker.com/linux/fedora/gpg | sudo gpg --dearmor -o "$KEYRING"
      sudo chmod a+r "$KEYRING"
    fi
    
    # Add repository
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo || {
      # Fallback: create repo file manually
      sudo tee "$REPO_FILE" >/dev/null <<EOF
[docker-ce-stable]
name=Docker CE Stable - \$basearch
baseurl=https://download.docker.com/linux/fedora/\$releasever/\$basearch/stable
enabled=1
gpgcheck=1
gpgkey=file://$KEYRING
EOF
    }
  fi
  sudo dnf makecache -y
}

ensure_subids() {
  local target_user="${SUDO_USER:-$USER}"
  local need=0
  grep -q "^$target_user:" /etc/subuid || need=1
  grep -q "^$target_user:" /etc/subgid || need=1
  if [[ $need -eq 1 ]]; then
    echo "🆔 Adding subuid/subgid ranges for $target_user…"
    sudo usermod --add-subuids 100000-165536 "$target_user"
    sudo usermod --add-subgids 100000-165536 "$target_user"
    echo "ℹ️ subuid/subgid updated. You may need to log out/in if start continues to fail."
  fi
}

write_user_env() {
  # Bake the *numeric* UID so DOCKER_HOST is always correct in new sessions
  local UID_NUM
  UID_NUM="$(id -u "$REAL_USER")"
  sudo -u "$REAL_USER" mkdir -p "$HOME_DIR/.config/environment.d"
  sudo -u "$REAL_USER" sh -c "cat >\"$HOME_DIR/.config/environment.d/docker-rootless.conf\" <<EOF
XDG_RUNTIME_DIR=/run/user/${UID_NUM}
DOCKER_HOST=unix:///run/user/${UID_NUM}/docker.sock
EOF"
}

apply_env_now() {
  export XDG_RUNTIME_DIR="/run/user/$(id -u "$REAL_USER")"
  export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/docker.sock"
}

cleanup_half_installed() {
  echo "🧽 Cleaning any half-installed rootless setup…"
  sudo -u "$REAL_USER" /usr/bin/dockerd-rootless-setuptool.sh uninstall -f >/dev/null 2>&1 || true
  sudo -u "$REAL_USER" rm -rf "$HOME_DIR/.local/share/docker" >/dev/null 2>&1 || true
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/systemd/user/docker.service" >/dev/null 2>&1 || true
  sudo -u "$REAL_USER" systemctl --user daemon-reload || true
}

verify_running() {
  if ! sudo -u "$REAL_USER" docker info >/dev/null 2>&1; then
    echo "❌ Cannot reach rootless Docker at ${DOCKER_HOST}"
    log_recent_unit "docker.service" 120
    return 1
  fi
  echo "✅ Rootless Docker is running at ${DOCKER_HOST}"
}

remove_conflicts() {
  if rpm -q docker >/dev/null 2>&1; then
    echo "🧹 Removing conflicting package: docker"
    sudo dnf remove -y docker || true
  fi
}

copy_zsh_config() {
  # ONLY copy the snippet; no sourcing edits.
  if [[ ! -f "$ZSH_SRC" ]]; then
    echo "⚠️  Zsh snippet not found at $ZSH_SRC (set ZSH_SRC to override). Skipping copy."
    return 0
  fi
  sudo -u "$REAL_USER" mkdir -p "$ZSH_DIR"
  sudo -u "$REAL_USER" cp -f "$ZSH_SRC" "$ZSH_TARGET"
  chown "$REAL_USER:$REAL_USER" "$ZSH_TARGET"
  echo "✅ Copied Zsh snippet → $ZSH_TARGET"
}

reload_shell_hint() {
  if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]]; then
    echo "🔄 GNOME on Xorg: Alt+F2 → r → Enter to reload."
  else
    echo "🔄 GNOME on Wayland: log out and back in to reload the shell."
  fi
}

# --- Rootful Docker guard -------------------------------------------------

ensure_rootful_docker_off() {
  echo "🛑 Ensuring rootful Docker is stopped/disabled/masked…"
  # Stop if running
  sudo systemctl stop docker.service docker.socket 2>/dev/null || true
  # Disable so it doesn't come back at boot
  sudo systemctl disable docker.service docker.socket 2>/dev/null || true
  # Mask to block socket activation
  sudo systemctl mask docker.service docker.socket 2>/dev/null || true
  # Remove legacy socket if present
  sudo rm -f /var/run/docker.sock 2>/dev/null || true
  echo "✅ Rootful Docker is disabled and socket removed (if present)."
}

# --- Start once then stop/disable (rootless) -----------------------------

start_user_docker_service_once() {
  echo "▶️  Starting user docker.service (temporary check)…"
  sudo -u "$REAL_USER" systemctl --user daemon-reload || true
  if ! sudo -u "$REAL_USER" systemctl --user start docker; then
    echo "❌ Failed to start user docker.service"
    log_recent_unit "docker.service" 120
    return 1
  fi

  # Wait for the socket, then verify
  for _ in {1..10}; do
    if sudo -u "$REAL_USER" docker info >/dev/null 2>&1; then break; fi
    sleep 1
  done
  verify_running

  echo "⏹  Stopping docker.service (manual start required next time)…"
  sudo -u "$REAL_USER" systemctl --user stop docker || true
  sudo -u "$REAL_USER" systemctl --user disable docker || true
  echo "ℹ️ Start it on demand with: systemctl --user start docker"
}

# --- GNOME extension via its own manage.sh -------------------------------

fetch_ext_repo() {
  local repo="$1" branch="$2" dest="$3"
  sudo -u "$REAL_USER" mkdir -p "$(dirname "$dest")"
  if [[ -d "$dest/.git" ]]; then
    sudo -u "$REAL_USER" git -C "$dest" fetch --all --prune || true
    sudo -u "$REAL_USER" git -C "$dest" checkout "$branch" || true
    sudo -u "$REAL_USER" git -C "$dest" pull --ff-only || true
  else
    sudo -u "$REAL_USER" rm -rf "$dest"
    sudo -u "$REAL_USER" git clone --branch "$branch" --depth 1 "$repo" "$dest"
  fi
}

ensure_user_extensions_allowed() {
  # Enable user extensions if globally disabled
  if command -v gsettings >/dev/null 2>&1; then
    if sudo -u "$REAL_USER" gsettings get org.gnome.shell disable-user-extensions 2>/dev/null | grep -q true; then
      sudo -u "$REAL_USER" gsettings set org.gnome.shell disable-user-extensions false || true
    fi
  fi
}

parse_uuid_from_metadata() {
  # $1 = path to metadata.json
  local md="$1"
  [[ -f "$md" ]] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -r '.uuid // empty' "$md" 2>/dev/null
  else
    grep -oE '"uuid"\s*:\s*"[^"]+"' "$md" | sed -E 's/.*"uuid"\s*:\s*"([^"]+)".*/\1/'
  fi
}

detect_extension_uuid() {
  # Heuristics to find the installed extension UUID after manage.sh install
  local uuid=""

  # 1) Any metadata.json in repo (root or first subdir)
  local md
  md="$(find "$GNOME_EXT_CACHE" -maxdepth 2 -type f -name metadata.json 2>/dev/null | head -n1 || true)"
  if [[ -n "$md" ]]; then
    uuid="$(parse_uuid_from_metadata "$md")"
  fi

  # 2) If still empty, search user's extensions by keyword
  if [[ -z "$uuid" ]]; then
    md="$(grep -rilE 'uuid|rootless|docker' "$HOME_DIR/.local/share/gnome-shell/extensions"/*/metadata.json 2>/dev/null | head -n1 || true)"
    if [[ -n "$md" ]]; then
      uuid="$(parse_uuid_from_metadata "$md")"
    fi
  fi

  # 3) As a last resort, try gnome-extensions list and pick a sensible match
  if [[ -z "$uuid" ]] && command -v gnome-extensions >/dev/null 2>&1; then
    uuid="$(sudo -u "$REAL_USER" gnome-extensions list 2>/dev/null | grep -E 'rootless|docker' | head -n1 || true)"
  fi

  [[ -n "$uuid" ]] && echo "$uuid"
}

enable_ext_with_gsettings() {
  local uuid="$1"
  [[ -n "$uuid" ]] || {
    echo "⚠️ enable_ext_with_gsettings: missing UUID"
    return 1
  }
  command -v gsettings >/dev/null 2>&1 || {
    echo "⚠️ gsettings not available"
    return 1
  }
  local cur new
  cur="$(sudo -u "$REAL_USER" gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "[]")"
  [[ "$cur" == *"'$uuid'"* ]] && {
    echo "ℹ️ Already enabled via gsettings: $uuid"
    return 0
  }
  new="${cur%]*}, '$uuid']"
  [[ "$cur" == "[]" ]] && new="['$uuid']"
  sudo -u "$REAL_USER" gsettings set org.gnome.shell enabled-extensions "$new"
  echo "✅ Enabled via gsettings: $uuid"
}

enable_extension() {
  local uuid="$1"
  [[ -n "$uuid" ]] || {
    echo "⚠️ enable_extension: missing UUID"
    return 1
  }

  ensure_user_extensions_allowed

  if command -v gext >/dev/null 2>&1; then
    if sudo -u "$REAL_USER" gext enable "$uuid"; then
      echo "✅ Enabled via gext: $uuid"
      return 0
    fi
  fi
  if command -v gnome-extensions >/dev/null 2>&1; then
    if sudo -u "$REAL_USER" gnome-extensions enable "$uuid"; then
      echo "✅ Enabled via gnome-extensions: $uuid"
      return 0
    fi
  fi

  # Last resort
  enable_ext_with_gsettings "$uuid" || {
    echo "⚠️ Could not enable extension automatically. UUID: $uuid"
    return 1
  }
}

install_gnome_extension() {
  echo "🧩 Installing GNOME extension (manage.sh) from: $GNOME_EXT_REPO ($GNOME_EXT_BRANCH)"
  command -v git >/dev/null 2>&1 || {
    echo "⚠️ git missing; installing…"
    sudo dnf install -y git
  }
  fetch_ext_repo "$GNOME_EXT_REPO" "$GNOME_EXT_BRANCH" "$GNOME_EXT_CACHE"

  if [[ ! -f "$GNOME_EXT_CACHE/manage.sh" ]]; then
    echo "❌ manage.sh not found in the extension repo. Aborting extension install."
    return 1
  fi

  (cd "$GNOME_EXT_CACHE" && sudo -u "$REAL_USER" chmod +x manage.sh && sudo -u "$REAL_USER" ./manage.sh install)

  # Detect UUID robustly and enable
  local uuid
  uuid="$(detect_extension_uuid || true)"
  if [[ -n "$uuid" ]]; then
    enable_extension "$uuid" || true
  else
    echo "⚠️ Could not determine extension UUID; skipping enable step."
  fi

  reload_shell_hint
}

uninstall_gnome_extension() {
  if [[ -f "$GNOME_EXT_CACHE/manage.sh" ]]; then
    echo "🗑 Uninstalling GNOME extension via manage.sh…"
    (cd "$GNOME_EXT_CACHE" && sudo -u "$REAL_USER" chmod +x manage.sh && sudo -u "$REAL_USER" ./manage.sh uninstall || true)
  else
    echo "ℹ️ Extension repo cache not found; skipping manage.sh uninstall."
  fi
}

# --- Actions -------------------------------------------------------------

install() {
  deps
  ensure_repo
  remove_conflicts

  echo "🐳 Installing Docker engine + CLI + rootless extras (no system daemon)…"
  sudo dnf install -y docker-ce docker-ce-cli docker-ce-rootless-extras

  # Make sure rootful is *really* off before rootless setup
  ensure_rootful_docker_off

  ensure_subids
  write_user_env
  apply_env_now
  sudo -u "$REAL_USER" systemctl --user daemon-reload || true

  echo "⚙️ Running rootless setup tool (idempotent)…"
  cleanup_half_installed
  if ! sudo -u "$REAL_USER" /usr/bin/dockerd-rootless-setuptool.sh install; then
    echo "❌ Setup tool failed. Printing logs (if any)…"
    log_recent_unit "docker.service" 120
    exit 1
  fi

  # Copy Zsh snippet (only copy, no sourcing edits)
  copy_zsh_config

  # Start once to verify, then stop & disable (user controls start)
  start_user_docker_service_once

  # Install + enable GNOME extension via its own manage.sh
  install_gnome_extension
}

config() {
  write_user_env
  apply_env_now
  sudo -u "$REAL_USER" systemctl --user daemon-reload || true

  # Make sure rootful is *really* off before reconfiguring rootless
  ensure_rootful_docker_off

  # Copy Zsh snippet (only copy, no sourcing edits)
  copy_zsh_config

  # Start once to verify, then stop & disable (user controls start)
  start_user_docker_service_once

  # Ensure GNOME extension present/enabled via its manage.sh
  install_gnome_extension
}

clean() {
  echo "🧹 Removing rootless Docker user service and env (packages kept)…"
  sudo -u "$REAL_USER" systemctl --user disable --now docker 2>/dev/null || true
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/systemd/user/docker.service" 2>/dev/null || true
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/environment.d/docker-rootless.conf" 2>/dev/null || true
  sudo -u "$REAL_USER" systemctl --user daemon-reload || true

  echo "🧽 Removing copied Zsh snippet…"
  sudo -u "$REAL_USER" rm -f "$ZSH_TARGET" 2>/dev/null || true

  echo "🧽 Uninstalling GNOME extension (manage.sh)…"
  uninstall_gnome_extension

  echo "🧽 Removing cached extension repo…"
  sudo -u "$REAL_USER" rm -rf "$HOME_DIR/.cache/glimt-rootless-ext" 2>/dev/null || true

  echo "🗑 Optional package removal (manual):"
  echo "    sudo dnf remove -y docker-ce docker-ce-cli docker-ce-rootless-extras"
  reload_shell_hint
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

