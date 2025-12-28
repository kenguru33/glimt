#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ dotnet userspace script failed on line $LINENO" >&2' ERR

# ======================================================
# Configuration
# ======================================================
ACTION="${1:-all}"

DOTNET_ROOT="$HOME/.dotnet"
DOTNET_BIN="$DOTNET_ROOT/dotnet"
INSTALLER="$DOTNET_ROOT/dotnet-install.sh"

SDK_CHANNELS=(8.0 10.0)

ENV_DIR="$HOME/.config/environment.d"
ENV_FILE="$ENV_DIR/dotnet.conf"

ZSH_DIR="$HOME/.zsh/config"
ZSH_FILE="$ZSH_DIR/dotnet.zsh"

log() { printf "[dotnet-userspace] %s\n" "$*" >&2; }

# ======================================================
# Install
# ======================================================
install_dotnet() {
  log "Preparing userspace directory"
  mkdir -p "$DOTNET_ROOT"

  if [[ ! -x "$INSTALLER" ]]; then
    log "Downloading dotnet-install.sh"
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$INSTALLER"
    chmod +x "$INSTALLER"
  fi

  for v in "${SDK_CHANNELS[@]}"; do
    log "Installing .NET SDK $v into $DOTNET_ROOT"
    "$INSTALLER" \
      --channel "$v" \
      --install-dir "$DOTNET_ROOT" \
      --no-path
  done

  log "Writing environment.d config (GUI + Rider)"
  mkdir -p "$ENV_DIR"
  cat >"$ENV_FILE" <<EOF
DOTNET_ROOT=%h/.dotnet
PATH=%h/.dotnet:%h/.dotnet/tools:%h/.local/bin:/usr/bin
EOF

  log "Writing Zsh config"
  mkdir -p "$ZSH_DIR"
  cat >"$ZSH_FILE" <<'EOF'
# .NET userspace configuration
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
EOF

  log "Verifying userspace dotnet (forced)"
  export DOTNET_ROOT="$DOTNET_ROOT"
  export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:/usr/bin"

  if [[ ! -x "$DOTNET_BIN" ]]; then
    echo "❌ dotnet binary missing at $DOTNET_BIN"
    exit 1
  fi

  "$DOTNET_BIN" --info
  "$DOTNET_BIN" --list-sdks

  cat <<EOF

✅ .NET userspace installation complete.

IMPORTANT:
• Log OUT and IN again (required for GUI apps like Rider)
• Restart Zsh or run:
    source $ZSH_FILE

Verification:
  dotnet --list-sdks
  dotnet --info

EOF
}

# ======================================================
# Clean
# ======================================================
clean_dotnet() {
  log "Removing userspace .NET installation"

  if [[ -d "$DOTNET_ROOT" ]]; then
    rm -rf "$DOTNET_ROOT"
    log "Removed $DOTNET_ROOT"
  else
    log "$DOTNET_ROOT not present"
  fi

  if [[ -f "$ENV_FILE" ]]; then
    rm -f "$ENV_FILE"
    log "Removed environment.d config"
  fi

  if [[ -f "$ZSH_FILE" ]]; then
    rm -f "$ZSH_FILE"
    log "Removed Zsh config"
  fi

  cat <<EOF

✅ Userspace .NET fully removed.

IMPORTANT:
• Log OUT and IN again to purge GUI environment
• Restart Zsh sessions

EOF
}

# ======================================================
# Dispatcher
# ======================================================
case "$ACTION" in
install | all)
  install_dotnet
  ;;
clean)
  clean_dotnet
  ;;
*)
  echo "Usage: $0 {install|clean|all}"
  exit 1
  ;;
esac
