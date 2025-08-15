#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="vscode"
ACTION="${1:-all}"

KEYRING="/etc/apt/keyrings/microsoft-vscode.gpg"
SOURCES="/etc/apt/sources.list.d/vscode.sources"

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
  apt-get update -y -qq
  apt-get install -y ca-certificates curl gnupg
  install -d -m 0755 /etc/apt/keyrings
}

install_repo() {
  echo "➕ [$MODULE_NAME] Adding Microsoft VS Code APT repo…"

  # Fjern gamle lister/nøkler for å unngå duplikater og gammelt oppsett
  rm -f /etc/apt/sources.list.d/vscode.list \
    /etc/apt/sources.list.d/code.list \
    /usr/share/keyrings/microsoft.gpg

  # (Re)last alltid nøkkelen, i tilfelle den er rotert
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc |
    gpg --dearmor -o "$KEYRING".tmp
  install -m 0644 "$KEYRING".tmp "$KEYRING"
  rm -f "$KEYRING".tmp

  # Bruk .sources-format + Signed-By, og lås til aktuell arkitektur
  cat >"$SOURCES" <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: $(dpkg --print-architecture)
Signed-By: $KEYRING
EOF
  chmod 0644 "$SOURCES"
}

remove_repo() {
  echo "➖ [$MODULE_NAME] Removing VS Code APT repo…"
  rm -f "$SOURCES" "$KEYRING"
}

install_pkg() {
  echo "📦 [$MODULE_NAME] Installing code…"
  apt-get update -y -qq
  apt-get install -y code
}

config() {
  echo "⚙️  [$MODULE_NAME] No extra VS Code config yet (using package defaults)."
  # Legg evt. utvidelser/innstillinger her senere:
  # su - "$SUDO_USER" -c "code --install-extension ms-python.python --force || true"
}

clean() {
  echo "🧹 [$MODULE_NAME] Purging VS Code and repo…"
  apt-get purge -y code || true
  remove_repo || true
  apt-get update -y -qq || true
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
