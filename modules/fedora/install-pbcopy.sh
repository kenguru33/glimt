#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="pbcopy"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

# === OS Check (Fedora only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "Error: Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "Error: This module supports Fedora/RHEL-based systems only."
  exit 1
fi

# === Deps ===
DEPS=(wl-clipboard xclip)

install_deps() {
  echo "Installing dependencies..."
  dnf_ensure "${DEPS[@]}"
}

install() {
  # Packages come from deps; only (re)install them here if they are missing
  local missing=()
  for pkg in "${DEPS[@]}"; do
    rpm -q "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  if (( ${#missing[@]} > 0 )); then
    install_deps
  else
    echo "wl-clipboard and xclip are installed"
  fi
}

config() {
  echo "Creating pbcopy/pbpaste wrappers in $HOME_DIR/.local/bin ..."
  BIN_DIR="$HOME_DIR/.local/bin"
  run_as_user mkdir -p "$BIN_DIR"

  # pbcopy -> wl-copy (Wayland) or xclip (X11 fallback)
  run_as_user tee "$BIN_DIR/pbcopy" >/dev/null <<'EOF'
#!/usr/bin/env bash
# macOS-like pbcopy using wl-copy (Wayland) or xclip (X11)
if command -v wl-copy >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  exec wl-copy "$@"
elif command -v xclip >/dev/null 2>&1; then
  exec xclip -selection clipboard "$@"
else
  echo "pbcopy: No clipboard tool found (install wl-clipboard or xclip)" >&2
  exit 1
fi
EOF

  # pbpaste -> wl-paste (Wayland) or xclip (X11 fallback)
  run_as_user tee "$BIN_DIR/pbpaste" >/dev/null <<'EOF'
#!/usr/bin/env bash
# macOS-like pbpaste using wl-paste (Wayland) or xclip (X11)
if command -v wl-paste >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
  exec wl-paste "$@"
elif command -v xclip >/dev/null 2>&1; then
  exec xclip -selection clipboard -o "$@"
else
  echo "pbpaste: No clipboard tool found (install wl-clipboard or xclip)" >&2
  exit 1
fi
EOF

  run_as_user chmod +x "$BIN_DIR/pbcopy" "$BIN_DIR/pbpaste"

  echo "ℹ️  Make sure ~/.local/bin is in PATH (it usually is)."
}

clean() {
  echo "Removing pbcopy/pbpaste wrappers..."
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.local/bin/pbcopy" "$HOME_DIR/.local/bin/pbpaste" || true

  # wl-clipboard/xclip may predate glimt and other tools rely on them, so
  # only remove them with explicit consent (confirm says no without a terminal)
  if rpm -q wl-clipboard >/dev/null 2>&1; then
    if confirm "Remove wl-clipboard as well?"; then
      sudo dnf remove -y wl-clipboard || true
    fi
  fi
  if rpm -q xclip >/dev/null 2>&1; then
    if confirm "Remove xclip as well?"; then
      sudo dnf remove -y xclip || true
    fi
  fi
}

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install
    ;;
  config)
    config
    ;;
  clean)
    clean
    ;;
  all)
    install_deps
    install
    config
    ;;
  *)
    echo "Usage: $0 {deps|install|config|clean|all}"
    exit 1
    ;;
esac

echo "Done ($MODULE_NAME: $ACTION)"


