#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="tableplus"
ACTION="${1:-all}"

KEYRING="/etc/apt/keyrings/tableplus.gpg"
SOURCES="/etc/apt/sources.list.d/tableplus.list"
GPG_KEY_URL="https://deb.tableplus.com/apt.tableplus.com.gpg.key"

require_sudo() {
  if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo -E -- "$0" "$ACTION"
  fi
}

is_debian_like() {
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID" == "ubuntu" || "$ID_LIKE" == *"debian"* ]]
}

detect_major_release() {
  local v
  if command -v lsb_release >/dev/null 2>&1; then
    v="$(lsb_release -rs 2>/dev/null || echo "")"
  else
    v=""
  fi
  if [[ -z "$v" && -r /etc/os-release ]]; then
    . /etc/os-release
    v="${VERSION_ID:-}"
  fi
  # Use major version only (e.g. 24.04 -> 24)
  printf "%s" "${v%%.*}"
}

deps() {
  echo "🔧 [$MODULE_NAME] Installing dependencies…"
  apt-get update -y -qq
  apt-get install -y ca-certificates curl gnupg
  install -d -m 0755 /etc/apt/keyrings
}

install_repo() {
  echo "➕ [$MODULE_NAME] Adding TablePlus APT repo…"
  rm -f "$SOURCES"

  curl -fsSL "$GPG_KEY_URL" | gpg --dearmor -o "$KEYRING".tmp
  install -m 0644 "$KEYRING".tmp "$KEYRING"
  rm -f "$KEYRING".tmp

  local major arch
  major="$(detect_major_release)"
  arch="$(dpkg --print-architecture)"
  if [[ "$arch" != "amd64" ]]; then
    echo "❌ TablePlus repo is amd64-only; current arch: $arch"
    exit 1
  fi
  if [[ -z "$major" ]]; then
    echo "❌ Could not detect OS major version for TablePlus repo."
    exit 1
  fi

  cat >"$SOURCES" <<EOF
deb [arch=amd64 signed-by=$KEYRING] https://deb.tableplus.com/debian/${major} tableplus main
EOF
  chmod 0644 "$SOURCES"
}

install_pkg() {
  echo "📦 [$MODULE_NAME] Installing tableplus…"
  apt-get update -y -qq
  apt-get install -y tableplus
}

config() {
  echo "⚙️  [$MODULE_NAME] No extra config yet."
}

clean() {
  echo "🧹 [$MODULE_NAME] Removing TablePlus and repo…"
  apt-get remove -y tableplus || true
  rm -f "$SOURCES" "$KEYRING"
  apt-get update -y -qq || true
  apt-get autoremove -y || true
}

main() {
  is_debian_like || {
    echo "❌ Debian-based systems only."
    exit 1
  }
  require_sudo
  case "$ACTION" in
    deps) deps ;;
    install)
      deps
      install_repo
      install_pkg
      ;;
    config) config ;;
    clean) clean ;;
    all)
      deps
      install_repo
      install_pkg
      config
      echo "✅ [$MODULE_NAME] Done."
      ;;
    *)
      echo "Usage: $0 [all|deps|install|config|clean]"
      exit 2
      ;;
  esac
}

main


