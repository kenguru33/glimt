#!/usr/bin/env bash
# modules/debian/disable-apt-fancy.sh
# Glimt module (Debian): disable apt/dpkg "fancy" progress bar.

set -euo pipefail
trap 'echo "❌ ${BASH_SOURCE[0]} failed at: $BASH_COMMAND" >&2' ERR

ACTION="${1:-all}"
CONF_OFF="/etc/apt/apt.conf.d/99zzz-no-fancy"

# Debian-only guard
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  [[ "${ID:-}" == "debian" ]] || { echo "❌ Debian-only. Detected ${ID:-unknown}"; exit 1; }
else
  echo "❌ Cannot detect OS (/etc/os-release missing)"; exit 1
fi

require_sudo() { sudo -v >/dev/null; }

disable_fancy() {
  require_sudo
  sudo tee "$CONF_OFF" >/dev/null <<'EOF'
DPKg::Progress-Fancy "0";
DPkg::Progress-Fancy "0";
Dpkg::Progress-Fancy "0";
Binary::apt::DPKg::Progress-Fancy "0";
Binary::apt::Dpkg::Progress-Fancy "0";
EOF
}

deps()    { echo "🔧 [deps] Nothing required."; }
install() { echo "🖥️ [install] Nothing to install."; }

config() {
  echo "🧼 [config] Disabling apt/dpkg fancy progress…"
  disable_fancy
  status
}

clean() {
  echo "🧹 [clean] Removing fancy-progress override…"
  require_sudo
  sudo rm -f "$CONF_OFF" || true
  status
}

status() {
  echo "🔎 [status] Effective settings:"
  apt-config dump | grep -i Dpkg::Progress-Fancy || true
  [[ -f "$CONF_OFF" ]] && echo " • Override file present: $CONF_OFF"
}

all() { deps; install; config; }

case "$ACTION" in
  all) all ;;
  deps) deps ;;
  install) install ;;
  config) config ;;
  clean) clean ;;
  status) status ;;
  *) echo "Usage: $(basename "$0") {all|deps|install|config|clean|status}" >&2; exit 2 ;;
esac
