#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="chrome"
ACTION="${1:-all}"

KEYRING="/etc/apt/keyrings/google-chrome.gpg"
SOURCES="/etc/apt/sources.list.d/google-chrome.sources"
DEFAULTS="/etc/default/google-chrome"

require_sudo() {
  if [[ "$(id -u)" -ne 0 ]]; then
    exec sudo -E -- "$0" "$ACTION"
  fi
}

is_debian() {
  [[ -r /etc/os-release ]] || return 1
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]
}

deps() {
  echo "🔧 [$MODULE_NAME] Installing dependencies…"
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -d -m 0755 /etc/apt/keyrings
}

write_defaults() {
  # Hindrer at Google legger global nøkkel i trusted.gpg.d eller reaktiverer repo etter dist-upgrade
  mkdir -p "$(dirname "$DEFAULTS")"
  cat >"$DEFAULTS" <<'EOF'
repo_add_once=false
repo_reenable_on_distupgrade=false
EOF
  chmod 0644 "$DEFAULTS"
}

install_repo() {
  echo "➕ [$MODULE_NAME] Adding Google Chrome APT repo…"

  # (Re)last alltid nøkkelen for å sikre riktig subkey-sett
  curl -fsSL https://dl.google.com/linux/linux_signing_key.pub |
    gpg --dearmor -o "$KEYRING".tmp
  install -m 0644 "$KEYRING".tmp "$KEYRING"
  rm -f "$KEYRING".tmp

  # Bytt til .sources-format med Signed-By
  cat >"$SOURCES" <<EOF
Types: deb
URIs: https://dl.google.com/linux/chrome/deb
Suites: stable
Components: main
Architectures: amd64
Signed-By: $KEYRING
EOF
  chmod 0644 "$SOURCES"

  write_defaults
}

remove_repo() {
  echo "➖ [$MODULE_NAME] Removing Google Chrome APT repo…"
  rm -f "$SOURCES"
  rm -f "$KEYRING"
  rm -f "$DEFAULTS"
}

install_pkg() {
  echo "📦 [$MODULE_NAME] Installing google-chrome-stable…"
  apt-get update -y
  apt-get install -y google-chrome-stable
}

config() {
  echo "⚙️  [$MODULE_NAME] No extra config. Using package defaults."
}

clean() {
  echo "🧹 [$MODULE_NAME] Purging Chrome and repo…"
  apt-get purge -y google-chrome-stable || true
  remove_repo || true
  apt-get update -y || true
  apt-get autoremove -y || true
}

all() {
  deps
  install_repo
  install_pkg
  config
  echo "✅ [$MODULE_NAME] Done."
}

main() {
  is_debian || {
    echo "❌ Debian-based systems only."
    exit 1
  }
  require_sudo
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
}

main
