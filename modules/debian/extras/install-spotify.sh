#!/usr/bin/env bash
# modules/debian/install-spotify.sh
# Glimt module: Install Spotify for Debian using the official APT repository.
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="spotify"
ACTION="${1:-all}"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

# ---- Debian-only guard ----
deb_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || die "Debian-only module."
  else
    die "Cannot detect OS."
  fi
}

# ---- Config ----
KEY_URL="https://download.spotify.com/debian/pubkey_C85668DF69375001.gpg"
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_FILE="$KEYRING_DIR/spotify.gpg"
LIST_FILE="/etc/apt/sources.list.d/spotify.list"
APT_LINE='deb [arch=amd64 signed-by=/etc/apt/keyrings/spotify.gpg] https://repository.spotify.com stable non-free'

require_amd64() {
  local arch
  arch="$(dpkg --print-architecture)"
  [[ "$arch" == "amd64" ]] || die "Spotify repo only ships amd64. Detected arch: $arch"
}

install_deps() {
  log "Installing dependencies (sudo): curl, gpg, ca-certificates, apt-transport-https"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends curl gpg ca-certificates apt-transport-https
}

setup_repo() {
  log "Configuring Spotify APT repository (keyrings + signed-by)"
  require_amd64
  sudo install -d -m 0755 "$KEYRING_DIR"
  curl -fsSL "$KEY_URL" | sudo gpg --dearmor --yes -o "$KEYRING_FILE"
  sudo chmod 0644 "$KEYRING_FILE"

  echo "$APT_LINE" | sudo tee "$LIST_FILE" >/dev/null
  sudo chmod 0644 "$LIST_FILE"
}

install_spotify() {
  setup_repo
  log "Installing spotify-client"
  sudo apt-get update -y
  sudo apt-get install -y spotify-client
}

configure_spotify() {
  # Placeholder for any future tweaks (desktop integration, MIME, etc.)
  true
}

clean_spotify() {
  log "Removing spotify-client and repository"
  sudo apt-get remove -y --purge spotify-client || true
  sudo rm -f "$LIST_FILE" || true
  sudo rm -f "$KEYRING_FILE" || true
  sudo apt-get update -y || true
  log "Clean complete."
}

# ---- Entry point ----
deb_guard

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    install_spotify
    ;;
  config)
    configure_spotify
    ;;
  clean)
    clean_spotify
    ;;
  all)
    install_deps
    install_spotify
    configure_spotify
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

log "Done: $ACTION"
