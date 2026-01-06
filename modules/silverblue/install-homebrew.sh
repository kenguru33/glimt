#!/usr/bin/env bash
# Glimt module: Homebrew (Linuxbrew)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ Homebrew module failed." >&2' ERR

MODULE_NAME="homebrew"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

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
  log "📦 Installing Homebrew dependencies..."

  . /etc/os-release

  if [[ "$ID" == "fedora" || "${ID_LIKE:-}" == *fedora* ]]; then
    sudo dnf install -y \
      curl file git procps-ng \
      gcc gcc-c++ make \
      glibc-devel
  elif [[ "$ID" == "debian" || "${ID_LIKE:-}" == *debian* ]]; then
    sudo apt update
    sudo apt install -y \
      curl file git procps \
      build-essential
  else
    log "⚠ Unsupported distro – skipping deps"
  fi
}

install() {
  require_user

  if [[ -x "$BREW_PREFIX/bin/brew" ]]; then
    log "✅ Homebrew already installed"
    return
  fi

  log "🍺 Installing Homebrew (user-space)..."

  sudo -u "$REAL_USER" bash <<EOF
set -e
NONINTERACTIVE=1 \
/bin/bash -c "\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
EOF
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

  chown "$REAL_USER:$REAL_USER" "$ENV_FILE"

  # Zsh integration (optional but nice)
  if [[ -d "$ZSH_CONFIG_DIR" ]]; then
    mkdir -p "$ZSH_CONFIG_DIR"
    cat >"$ZSH_FILE" <<'EOF'
# Homebrew (Linuxbrew)
if [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
  eval "$($HOME/.linuxbrew/bin/brew shellenv)"
fi
EOF
    chown "$REAL_USER:$REAL_USER" "$ZSH_FILE"
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
