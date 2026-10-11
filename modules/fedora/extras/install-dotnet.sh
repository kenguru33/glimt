#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="dotnet-userspace"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

# ======================================================
# Configuration
# ======================================================
ACTION="${1:-all}"

DOTNET_ROOT="$HOME_DIR/.dotnet"
INSTALLER="$DOTNET_ROOT/dotnet-install.sh"

# Channels track the latest SDK of each line (intentionally not pinned)
SDK_CHANNELS=(8.0 10.0)

ENV_DIR="$HOME_DIR/.config/environment.d"
ENV_FILE="$ENV_DIR/dotnet.conf"

ZSH_DIR="$HOME_DIR/.zsh/config"
ZSH_FILE="$ZSH_DIR/dotnet.zsh"
ZSH_TEMPLATE="$(dirname "${BASH_SOURCE[0]}")/../config/dotnet.zsh"

# ---- Fedora-only guard ----
fedora_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "${ID:-}" == "fedora" || "${ID_LIKE:-}" == *"fedora"* || "${ID:-}" == "rhel" ]] || die "Fedora/RHEL-only module."
  else
    die "Cannot detect OS."
  fi
}

# ======================================================
# Dependencies
# ======================================================
install_deps() {
  log "Installing dependencies"
  # curl for dotnet-install.sh; libicu is required by the .NET runtime
  sudo dnf install -y curl libicu
}

# ======================================================
# Install
# ======================================================
install_dotnet() {
  log "Preparing userspace directory"
  run_as_user mkdir -p "$DOTNET_ROOT"

  if [[ ! -x "$INSTALLER" ]]; then
    log "Downloading dotnet-install.sh"
    run_as_user curl -fsSL https://dot.net/v1/dotnet-install.sh -o "$INSTALLER"
    run_as_user chmod +x "$INSTALLER"
  fi

  local v
  for v in "${SDK_CHANNELS[@]}"; do
    log "Installing .NET SDK $v into $DOTNET_ROOT"
    run_as_user "$INSTALLER" \
      --channel "$v" \
      --install-dir "$DOTNET_ROOT" \
      --no-path
  done

  PATH="$DOTNET_ROOT:$PATH" DOTNET_ROOT="$DOTNET_ROOT" verify_binary dotnet --list-sdks
}

# ======================================================
# Config
# ======================================================
config_dotnet() {
  log "Writing environment.d config (GUI + Rider)"
  run_as_user mkdir -p "$ENV_DIR"
  run_as_user tee "$ENV_FILE" >/dev/null <<'ENVEOF'
DOTNET_ROOT=%h/.dotnet
PATH=%h/.dotnet:%h/.dotnet/tools:%h/.local/bin:/usr/bin
ENVEOF

  log "Deploying Zsh config"
  deploy_config "$ZSH_TEMPLATE" "$ZSH_FILE"

  cat <<MSG

✅ .NET userspace installation complete.

IMPORTANT:
• Log OUT and IN again (required for GUI apps like Rider)
• Restart Zsh or run:
    source $ZSH_FILE

Verification:
  dotnet --list-sdks
  dotnet --info

MSG
}

# ======================================================
# Clean
# ======================================================
clean_dotnet() {
  log "Removing userspace .NET installation"

  if [[ -d "$DOTNET_ROOT" ]]; then
    run_as_user rm -rf "$DOTNET_ROOT"
    log "Removed $DOTNET_ROOT"
  else
    log "$DOTNET_ROOT not present"
  fi

  if [[ -f "$ENV_FILE" ]]; then
    run_as_user rm -f "$ENV_FILE"
    log "Removed environment.d config"
  fi

  if [[ -f "$ZSH_FILE" ]]; then
    run_as_user rm -f "$ZSH_FILE"
    log "Removed Zsh config"
  fi

  cat <<MSG

✅ Userspace .NET fully removed.

IMPORTANT:
• Log OUT and IN again to purge GUI environment
• Restart Zsh sessions

MSG
}

# ======================================================
# Dispatcher
# ======================================================
fedora_guard

case "$ACTION" in
deps)
  install_deps
  ;;
install)
  install_dotnet
  ;;
config)
  config_dotnet
  ;;
clean)
  clean_dotnet
  ;;
all)
  install_deps
  install_dotnet
  config_dotnet
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac
