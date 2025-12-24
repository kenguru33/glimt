#!/bin/bash
set -e
trap 'echo "❌ wl-copy module failed at: $BASH_COMMAND" >&2' ERR

# === Metadata ===
MODULE_NAME="wl-copy"
ACTION="${1:-all}"

# Run as real user even if invoked via sudo
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

# === OS Check (Debian only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
  echo "❌ This module supports Debian only."
  exit 1
fi

# === Deps ===
DEPS=(wl-clipboard xclip)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo apt update -y
  sudo apt install -y "${DEPS[@]}"
}

install() {
  echo "✅ Ensuring wl-clipboard is installed..."
  sudo apt install -y wl-clipboard
}

config() {
  echo "⚙️  Creating pbcopy/pbpaste wrappers in $HOME_DIR/.local/bin ..."
  BIN_DIR="$HOME_DIR/.local/bin"
  sudo -u "$REAL_USER" mkdir -p "$BIN_DIR"
  chown -R "$REAL_USER":"$REAL_USER" "$BIN_DIR"

  # pbcopy -> wl-copy (Wayland) or xclip (X11 fallback)
  cat > "$BIN_DIR/pbcopy" <<'EOF'
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
  cat > "$BIN_DIR/pbpaste" <<'EOF'
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

  chmod +x "$BIN_DIR/pbcopy" "$BIN_DIR/pbpaste"
  chown "$REAL_USER":"$REAL_USER" "$BIN_DIR/pbcopy" "$BIN_DIR/pbpaste"

  echo "ℹ️  Make sure ~/.local/bin is in PATH (it usually is)."
}

clean() {
  echo "🧹 Removing pbcopy/pbpaste wrappers..."
  rm -f "$HOME_DIR/.local/bin/pbcopy" "$HOME_DIR/.local/bin/pbpaste" || true

  echo "🧽 Optionally removing wl-clipboard..."
  if dpkg -s wl-clipboard >/dev/null 2>&1; then
    sudo apt remove -y wl-clipboard || true
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

echo "✅ Done ($MODULE_NAME: $ACTION)"
