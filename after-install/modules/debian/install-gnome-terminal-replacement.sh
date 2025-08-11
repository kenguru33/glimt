#!/bin/bash
set -euo pipefail
trap 'echo "❌ ${BASH_COMMAND} failed (line $LINENO)"; exit 1' ERR

ACTION="${1:-all}"

# --- OS guard (Debian/derivatives) ---
if [[ -f /etc/os-release ]]; then . /etc/os-release; else
  echo "❌ Cannot detect OS"
  exit 1
fi
if [[ "$ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
  echo "❌ This script targets Debian/derivatives."
  exit 1
fi

# Paths
USER_BIN="$HOME/.local/bin"
WRAPPER="$USER_BIN/terminal"
SHIM_DIR="/usr/local/bin"
SHIM="$SHIM_DIR/gnome-terminal"

deps() {
  echo "📦 Ensuring basics..."
  sudo apt update -y
  # No heavy deps needed; keep it lean. kitty/kgx/blackbox are optional, use whatever you already have.
  sudo apt install -y libglib2.0-bin >/dev/null 2>&1 || true
}

install_wrapper() {
  echo "🧰 Installing user 'terminal' wrapper → $WRAPPER"
  mkdir -p "$USER_BIN"
  cat >"$WRAPPER" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

# Parse a few common --working-directory / -e usages
WORKDIR="$PWD"
CMD=""
ARGS=("$@")
i=0
while (( i < ${#ARGS[@]} )); do
  a="${ARGS[$i]}"
  case "$a" in
    --working-directory=*)
      WORKDIR="${a#*=}"
      ;;
    --working-directory)
      ((i++)); WORKDIR="${ARGS[$i]:-$WORKDIR}"
      ;;
    -e|--execute)
      CMD="${ARGS[@]:$((i+1))}"
      break
      ;;
    --)
      CMD="${ARGS[@]:$((i+1))}"
      break
      ;;
  esac
  ((i++))
done

prefer_blackbox() {
  command -v blackbox-terminal >/dev/null 2>&1 || command -v blackbox >/dev/null 2>&1
}

if [[ -z "$CMD" ]]; then
  if prefer_blackbox; then
    exec blackbox-terminal --working-directory "$WORKDIR"
  elif command -v kgx >/dev/null 2>&1; then
    exec kgx -- bash -lc "cd '$WORKDIR'; exec \$SHELL -l"
  elif command -v kitty >/dev/null 2>&1; then
    exec kitty --directory "$WORKDIR"
  else
    exec x-terminal-emulator
  fi
else
  # command requested (best handled by kgx/kitty)
  if command -v kgx >/dev/null 2>&1; then
    exec kgx -- bash -lc "cd '$WORKDIR'; $CMD; exec \$SHELL -l"
  elif command -v kitty >/dev/null 2>&1; then
    exec kitty --directory "$WORKDIR" bash -lc "cd '$WORKDIR'; $CMD; exec \$SHELL -l"
  elif prefer_blackbox; then
    exec blackbox-terminal --working-directory "$WORKDIR"
  else
    exec x-terminal-emulator -e bash -lc "cd '$WORKDIR'; $CMD"
  fi
fi
SH
  chmod +x "$WRAPPER"
  echo "✅ Wrapper installed."
}

install_shim() {
  echo "🪄 Installing system shim for 'gnome-terminal' → $SHIM"
  sudo install -d "$SHIM_DIR"
  # This shim finds the real user's home even if called via sudo
  sudo tee "$SHIM" >/dev/null <<'SH'
#!/usr/bin/env bash
set -euo pipefail
# Resolve invoking user's HOME (works if called normally or via sudo)
if [[ -n "${SUDO_USER-}" ]]; then
  USER_HOME="$(eval echo "~$SUDO_USER")"
else
  USER_HOME="$HOME"
fi
exec "$USER_HOME/.local/bin/terminal" "$@"
SH
  sudo chmod +x "$SHIM"
  echo "✅ Shim installed."
}

config_extension() {
  echo "⚙️ Pointing Nautilus extension at 'terminal' and enabling new-tab..."
  gsettings set com.github.stunkymonkey.nautilus-open-any-terminal terminal 'terminal' || true
  gsettings set com.github.stunkymonkey.nautilus-open-any-terminal new-tab true || true

  echo "🔄 Restarting Nautilus..."
  nautilus -q || true
  echo "✅ Config applied."
}

remove_gnome() {
  echo "🗑 Removing GNOME Terminal and its Nautilus provider (optional step)..."
  sudo apt remove --purge -y gnome-terminal nautilus-extension-gnome-terminal || true
  echo "🔄 Restarting Nautilus..."
  nautilus -q || true
  echo "✅ GNOME Terminal removed."
}

clean() {
  echo "🧹 Cleaning wrapper and shim..."
  rm -f "$WRAPPER"
  if [[ -w "$SHIM" ]] || sudo test -e "$SHIM"; then
    sudo rm -f "$SHIM"
  fi
  echo "🔄 Restarting Nautilus..."
  nautilus -q || true
  echo "✅ Clean complete."
}

case "$ACTION" in
deps) deps ;;
install)
  deps
  install_wrapper
  install_shim
  ;;
config) config_extension ;;
remove-gnome) remove_gnome ;;
clean) clean ;;
all)
  deps
  install_wrapper
  install_shim
  config_extension
  ;;
*)
  echo "Usage: $0 [all|deps|install|config|remove-gnome|clean]"
  exit 2
  ;;
esac
