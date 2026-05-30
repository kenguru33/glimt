#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="dotnet-userspace"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

macos_guard() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
}

DOTNET_ROOT="$HOME_DIR/.dotnet"
DOTNET_BIN="$DOTNET_ROOT/dotnet"
INSTALLER="$DOTNET_ROOT/dotnet-install.sh"

SDK_CHANNELS=(8.0 10.0)

ZSH_DIR="$HOME_DIR/.zsh/config"
ZSH_FILE="$ZSH_DIR/dotnet.zsh"

deps() { log "No additional dependencies."; }

install() {
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

  log "Writing Zsh config"
  mkdir -p "$ZSH_DIR"
  cat >"$ZSH_FILE" <<'EOF'
# .NET userspace configuration
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"
EOF

  export DOTNET_ROOT="$DOTNET_ROOT"
  export PATH="$DOTNET_ROOT:$DOTNET_ROOT/tools:$PATH"

  [[ -x "$DOTNET_BIN" ]] || die "dotnet binary missing at $DOTNET_BIN"

  "$DOTNET_BIN" --list-sdks

  cat <<EOF

✅ .NET userspace installation complete.

Restart your terminal or run:
  source $ZSH_FILE

Verify:
  dotnet --list-sdks
  dotnet --info

EOF
}

config() { log "No extra configuration needed."; }

clean() {
  log "Removing userspace .NET installation"

  [[ -d "$DOTNET_ROOT" ]] && { rm -rf "$DOTNET_ROOT"; log "Removed $DOTNET_ROOT"; }
  [[ -f "$ZSH_FILE" ]]    && { rm -f "$ZSH_FILE";    log "Removed Zsh config"; }

  cat <<EOF

✅ Userspace .NET fully removed. Restart your terminal.

EOF
}

macos_guard

case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
