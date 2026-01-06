#!/usr/bin/env bash
# Glimt module: Homebrew (Linuxbrew)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ Homebrew module failed." >&2' ERR

MODULE_NAME="homebrew"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="${HOME:-$(eval echo "~$REAL_USER")}"

BREW_PREFIX="$HOME_DIR/.linuxbrew"
ENV_DIR="$HOME_DIR/.config/environment.d"
ENV_FILE="$ENV_DIR/99-homebrew.conf"

ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_FILE="$ZSH_CONFIG_DIR/homebrew.zsh"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_user() {
  if [[ "$EUID" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    echo "❌ Do not run this module as root directly." >&2
    exit 1
  fi
}

deps() {
  log "📦 Checking Homebrew dependencies..."

  . /etc/os-release

  # Required commands for Homebrew
  local missing_deps=()
  local required_commands=("curl" "file" "git")
  
  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing_deps+=("$cmd")
    fi
  done

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log "❌ Missing required dependencies: ${missing_deps[*]}"
    log "ℹ️  For Silverblue, install these via rpm-ostree:"
    log "   sudo rpm-ostree install -y ${missing_deps[*]}"
    log "   Then reboot and run this script again."
    exit 1
  fi

  # Check for build tools (optional but recommended)
  local build_tools=("gcc" "make")
  local missing_build_tools=()
  for tool in "${build_tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      missing_build_tools+=("$tool")
    fi
  done

  if [[ ${#missing_build_tools[@]} -gt 0 ]]; then
    log "⚠️  Build tools not found: ${missing_build_tools[*]}"
    log "ℹ️  Some Homebrew packages may fail to compile without these"
    log "   Install via: sudo rpm-ostree install -y gcc gcc-c++ make"
  else
    log "✅ All dependencies available"
  fi
}

install() {
  require_user

  if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
    log "✅ Homebrew already installed"
    return
  fi

  log "🍺 Installing Homebrew (user-space)..."

  # Run Homebrew installer as current user (no sudo needed)
  NONINTERACTIVE=1 \
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

config() {
  require_user

  log "🛠 Configuring Homebrew environment..."

  mkdir -p "$ENV_DIR"
  cat >"$ENV_FILE" <<EOF
PATH=$BREW_PREFIX/bin:$BREW_PREFIX/sbin:\$PATH
HOMEBREW_PREFIX=$BREW_PREFIX
HOMEBREW_CELLAR=$BREW_PREFIX/Cellar
HOMEBREW_REPOSITORY=$BREW_PREFIX/Homebrew
EOF

  # Zsh integration (optional but nice)
  if [[ -d "$ZSH_CONFIG_DIR" ]] || [[ -n "${ZSH_CONFIG_DIR:-}" ]]; then
    mkdir -p "$ZSH_CONFIG_DIR"
    cat >"$ZSH_FILE" <<'EOF'
# Homebrew (Linuxbrew)
if [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
  eval "$($HOME/.linuxbrew/bin/brew shellenv)"
fi
EOF
    log "✅ Zsh config installed"
  fi

  log "ℹ Log out and back in (or reboot) for GUI apps to see Homebrew"
}

clean() {
  require_user

  log "🧹 Removing Homebrew..."

  rm -rf "$BREW_PREFIX"
  rm -f "$ENV_FILE"
  rm -f "$ZSH_FILE"

  log "✅ Homebrew removed"
}

case "$ACTION" in
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
all)
  deps
  install
  config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac
