#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ lazydocker: error on line $LINENO" >&2' ERR

MODULE_NAME="lazydocker"
ACTION="${1:-all}"

# --- Config (override via env) ----------------------------------------------
# If set, pins to a specific release tag (e.g., v0.23.3). If empty, uses upstream installer to fetch latest.
LAZYDOCKER_VERSION="${LAZYDOCKER_VERSION:-}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
WRAPPER="${WRAPPER:-$BIN_DIR/lazydocker-rootless}"
DESKTOP_FILE="${DESKTOP_FILE:-$HOME/.local/share/applications/lazydocker.desktop}"

export PATH=$HOME/.local/bin:$PATH

# --- Debian-only guard -------------------------------------------------------
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || {
    echo "❌ Debian only."
    exit 1
  }
else
  echo "❌ Cannot detect OS."
  exit 1
fi

# --- Helpers -----------------------------------------------------------------
as_root() {
  sudo -n true 2>/dev/null || true
  sudo "$@"
}
require_cmd() { command -v "$1" >/dev/null 2>&1 || {
  echo "Missing: $1"
  exit 1
}; }

map_arch() {
  local arch
  arch="$(dpkg --print-architecture)"
  case "$arch" in
  amd64) echo "x86_64" ;;
  arm64) echo "arm64" ;;
  *)
    echo "❌ Unsupported architecture: $arch"
    exit 1
    ;;
  esac
}

deps() {
  echo "==> [$MODULE_NAME] deps"
  as_root apt-get update -y
  as_root apt-get install -y curl tar xz-utils ca-certificates
}

_download_from_release() {
  require_cmd curl
  require_cmd tar
  mkdir -p "$BIN_DIR"

  local tag="$LAZYDOCKER_VERSION"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "❌ LAZYDOCKER_VERSION must look like v0.23.3 (got: $tag)"
    exit 1
  }

  local arch fname url tmpdir
  arch="$(map_arch)"
  # LazyDocker assets look like: lazydocker_0.23.3_Linux_x86_64.tar.gz
  fname="lazydocker_${tag#v}_Linux_${arch}.tar.gz"
  url="https://github.com/jesseduffield/lazydocker/releases/download/${tag}/${fname}"

  tmpdir="$(mktemp -d)"
  echo "==> Downloading $url"
  curl -fL "$url" -o "$tmpdir/$fname"
  echo "==> Extracting"
  tar -xzf "$tmpdir/$fname" -C "$tmpdir"
  install -m 0755 "$tmpdir/lazydocker" "$BIN_DIR/lazydocker"
  rm -rf "$tmpdir"
}

_download_latest_via_upstream_script() {
  # No pipe-to-bash: download to tmp, then execute locally.
  require_cmd curl
  mkdir -p "$BIN_DIR"
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh" -o "$tmp"
  chmod +x "$tmp"
  # The script installs to /usr/local/bin by default; override by setting DIR
  DIR="$BIN_DIR" "$tmp"
  rm -f "$tmp"
}

install_pkg() {
  echo "==> [$MODULE_NAME] install"
  if [[ -n "$LAZYDOCKER_VERSION" ]]; then
    _download_from_release
  else
    _download_latest_via_upstream_script
  fi
  echo "✅ Installed: $(command -v lazydocker || echo "$BIN_DIR/lazydocker")"
}

write_wrapper() {
  echo "==> Writing rootless-aware wrapper: $WRAPPER"
  mkdir -p "$BIN_DIR"
  cat >"$WRAPPER" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
UID_NUM="$(id -u)"
DEFAULT_SOCK="unix:///run/user/${UID_NUM}/docker.sock"
# Use existing DOCKER_HOST if set, else default to rootless sock
export DOCKER_HOST="${DOCKER_HOST:-$DEFAULT_SOCK}"
exec lazydocker "$@"
SH
  chmod +x "$WRAPPER"
  echo "   Run: $WRAPPER"
}

write_desktop_entry() {
  echo "==> Writing desktop entry: $DESKTOP_FILE"
  mkdir -p "$(dirname "$DESKTOP_FILE")"
  # Desktop will open in whatever your system's default terminal is (GNOME uses org.gnome.Terminal by default).
  cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=LazyDocker (rootless)
Comment=Terminal UI for managing Docker
Type=Application
Exec=${WRAPPER}
Terminal=true
Categories=Development;System;
Icon=utilities-terminal
EOF
  update-desktop-database "$(dirname "$DESKTOP_FILE")" >/dev/null 2>&1 || true
}

config() {
  # Binary presence
  command -v lazydocker >/dev/null 2>&1 || {
    echo "❌ lazydocker binary not found; run install first."
    exit 1
  }
  write_wrapper
  write_desktop_entry
  echo "==> Verify it talks to your rootless daemon (start your user service if you keep it disabled):"
  echo "    systemctl --user start docker    # if needed"
  echo "    DOCKER_HOST=\$DOCKER_HOST lazydocker  # or simply: $WRAPPER"
}

clean() {
  echo "==> [$MODULE_NAME] clean"
  rm -f "$WRAPPER" 2>/dev/null || true
  rm -f "$DESKTOP_FILE" 2>/dev/null || true
  # Remove main binary only if it lives under our BIN_DIR to avoid clobbering system installs
  if [[ -f "$BIN_DIR/lazydocker" ]]; then
    rm -f "$BIN_DIR/lazydocker"
  fi
  echo "Done."
}

case "$ACTION" in
deps) deps ;;
install)
  deps
  install_pkg
  ;;
config) config ;;
clean) clean ;;
all)
  deps
  install_pkg
  config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}  [env: LAZYDOCKER_VERSION=vX.Y.Z]"
  exit 1
  ;;
esac
