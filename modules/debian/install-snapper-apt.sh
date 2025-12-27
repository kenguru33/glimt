#!/usr/bin/env bash
# Glimt module: Enable Snapper integration with APT (Debian)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="snapper-apt"
ACTION="${1:-all}"

APT_HOOK="/etc/apt/apt.conf.d/80snapper"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die() {
  printf "ERROR: %s\n" "$*" >&2
  exit 1
}

deb_guard() {
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || die "Debian-only module."
}

snapper_ready() {
  command -v snapper >/dev/null || return 1
  snapper list-configs 2>/dev/null | grep -q '^root'
}

deps() {
  deb_guard
  log "No extra dependencies required"
}

install() {
  deb_guard
  log "Nothing to install (APT hook based)"
}

config() {
  deb_guard

  if ! snapper_ready; then
    die "Snapper root config not found. Install/configure Snapper first."
  fi

  log "Installing APT Snapper hook"

  sudo tee "$APT_HOOK" >/dev/null <<'EOF'
DPkg::Pre-Invoke {
  "if command -v snapper >/dev/null 2>&1; then snapper -c root create -t pre -p -d 'apt pre-upgrade'; fi";
};

DPkg::Post-Invoke {
  "if command -v snapper >/dev/null 2>&1; then snapper -c root create -t post -p -d 'apt post-upgrade'; fi";
};
EOF
}

clean() {
  deb_guard

  if [[ -f "$APT_HOOK" ]]; then
    log "Removing APT Snapper hook"
    sudo rm -f "$APT_HOOK"
  else
    log "APT Snapper hook not present"
  fi
}

case "$ACTION" in
all)
  deps
  install
  config
  ;;
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  die "Unknown action: $ACTION (use: all | deps | install | config | clean)"
  ;;
esac
