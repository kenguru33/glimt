#!/bin/bash
# modules/debian/dockge-rootless.sh
# Glimt module: Install Dockge for ROOTLESS Docker
# - Verifies/installs rootless Docker via modules/debian/docker-rootless.sh
# - Uses ${XDG_RUNTIME_DIR}/docker.sock
# - Optional user-service autostart (depends on rootless docker.service)
# - Pattern: all | deps | install | config | clean

set -euo pipefail
trap 'echo "❌ dockge-rootless: error on line $LINENO" >&2' ERR

MODULE_NAME="dockge-rootless"
ACTION="${1:-all}"

# === Config (override with env) ===
DOCKGE_DIR="${DOCKGE_DIR:-$HOME/.local/share/dockge}"
STACKS_DIR="${STACKS_DIR:-$HOME/docker/stacks}"
DOCKGE_PORT="${DOCKGE_PORT:-5001}"
COMPOSE_FILE="$DOCKGE_DIR/compose.yaml"
DOCKGE_AUTOSTART="${DOCKGE_AUTOSTART:-true}"

# Glimt root & docker-rootless module path
GLIMT_ROOT="${GLIMT_ROOT:-$HOME/.glimt}"
DOCKER_ROOTLESS_MODULE="${DOCKER_ROOTLESS_MODULE:-$GLIMT_ROOT/modules/debian/docker-rootless.sh}"

# Rootless socket env
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
export DOCKER_HOST="${DOCKER_HOST:-unix://$XDG_RUNTIME_DIR/docker.sock}"

# === Debian-only guard ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || { echo "❌ Debian only."; exit 1; }
else
  echo "❌ Cannot detect OS."
  exit 1
fi

log_recent_unit() {
  local unit="$1" lines="${2:-80}"
  echo "----- logs: $unit (last ${lines}) -----"
  journalctl --user -u "$unit" -n "$lines" --no-pager || true
  echo "-----------------------------------------------------------------"
}

have_rootless_installed() {
  # dockerd binary present?
  command -v dockerd >/dev/null 2>&1 || return 1
  # rootless extras present?
  dpkg -s docker-ce-rootless-extras >/dev/null 2>&1 || dpkg -s docker.io >/dev/null 2>&1 || return 1
  # setup tool present?
  command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1 || return 1
  return 0
}

ensure_rootless_installed() {
  if have_rootless_installed; then
    return 0
  fi

  echo "ℹ️ Rootless Docker not detected. Attempting to install via: $DOCKER_ROOTLESS_MODULE"
  if [[ ! -x "$DOCKER_ROOTLESS_MODULE" ]]; then
    echo "❌ Cannot find executable docker-rootless module at: $DOCKER_ROOTLESS_MODULE"
    echo "   Set DOCKER_ROOTLESS_MODULE to the correct path or install rootless Docker manually."
    exit 1
  fi

  "$DOCKER_ROOTLESS_MODULE" all
}

need_rootless_docker() {
  # Ensure installed first (may run installer)
  ensure_rootless_installed

  # CLI must exist
  command -v docker >/dev/null 2>&1 || { echo "❌ docker CLI not found"; exit 1; }

  # Start rootless docker if not running
  if ! docker info >/dev/null 2>&1; then
    echo "ℹ️ Rootless Docker not running, trying to start user docker.service..."
    if ! systemctl --user start docker; then
      echo "❌ Failed to start rootless docker.service"
      log_recent_unit "docker.service" 80
      exit 1
    fi
    # Wait for the socket
    echo -n "⏳ Waiting for docker.sock..."
    for _ in {1..15}; do
      if docker info >/dev/null 2>&1; then
        echo " ready."
        break
      fi
      sleep 1
    done
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "❌ Cannot reach rootless Docker at $DOCKER_HOST"
    log_recent_unit "docker.service" 100
    exit 1
  fi

  if ! docker compose version >/dev/null 2>&1; then
    echo "❌ 'docker compose' plugin missing"; exit 1
  fi
}

deps() {
  command -v curl >/dev/null 2>&1 || { echo "❌ curl required"; exit 1; }
}

install() {
  need_rootless_docker

  echo "📁 Creating directories…"
  mkdir -p "$DOCKGE_DIR" "$STACKS_DIR"

  echo "⬇️  Fetching Dockge compose (port=$DOCKGE_PORT, stacks=$STACKS_DIR)…"
  curl -fsSL "https://dockge.kuma.pet/compose.yaml?port=${DOCKGE_PORT}&stacksPath=${STACKS_DIR}" -o "$COMPOSE_FILE"

  echo "🔧 Patching compose to use rootless socket…"
  sed -i 's#/var/run/docker\.sock#${XDG_RUNTIME_DIR}/docker.sock#g' "$COMPOSE_FILE"

  echo "🚀 Starting Dockge…"
  (cd "$DOCKGE_DIR" && docker compose up -d)
  echo "✅ Dockge is up at http://localhost:${DOCKGE_PORT}"
}

config() {
  need_rootless_docker

  echo "🔧 Creating systemd --user unit for Dockge…"
  local unit_dir="$HOME/.config/systemd/user"
  local unit_file="$unit_dir/dockge.service"
  mkdir -p "$unit_dir"
  cat > "$unit_file" <<EOF
[Unit]
Description=Dockge (user / rootless)
After=docker.service
Wants=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$DOCKGE_DIR
Environment=DOCKER_HOST=$DOCKER_HOST
Environment=XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=0

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  if [[ "$DOCKGE_AUTOSTART" == "true" ]]; then
    systemctl --user enable --now dockge.service || true
    echo "ℹ️ Autostart enabled. For pre-login start: sudo loginctl enable-linger \"$USER\""
  else
    echo "ℹ️ Autostart disabled. Start manually with: systemctl --user start dockge"
  fi
}

clean() {
  echo "🧹 Stopping Dockge (user service, if any)…"
  systemctl --user disable --now dockge.service 2>/dev/null || true
  rm -f "$HOME/.config/systemd/user/dockge.service" 2>/dev/null || true
  systemctl --user daemon-reload || true

  if [[ -f "$COMPOSE_FILE" ]]; then
    (cd "$DOCKGE_DIR" && docker compose down || true)
  fi

  # Keep stacks by default; uncomment to wipe Dockge data:
  # rm -rf "$DOCKGE_DIR" "$STACKS_DIR"
  echo "ℹ️ Stacks kept at: $STACKS_DIR"
}

case "$ACTION" in
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  all)     deps; install; config ;;
  *) echo "Usage: $0 {all|deps|install|config|clean}"; exit 1 ;;
esac
