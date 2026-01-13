#!/usr/bin/env bash
# Glimt module: zellij
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ [zellij] installer failed at line $LINENO" >&2' ERR

MODULE_NAME="zellij"
ACTION="${1:-all}"

# --------------------------------------------------
# User context
# --------------------------------------------------
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

ZELLIJ_CONFIG_DIR="$HOME_DIR/.config/zellij"
ZELLIJ_CONFIG_FILE="$ZELLIJ_CONFIG_DIR/config.kdl"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_TARGET_CONFIG="$ZSH_CONFIG_DIR/zellij.zsh"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

die() {
  echo "❌ [$MODULE_NAME] $*" >&2
  exit 1
}

require_user() {
  if [[ "$EUID" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    die "Do not run this module as root directly"
  fi
}

# --------------------------------------------------
# Repo layout
#
# repo-root/
# ├── config/zellij.zsh
# └── modules/install-zellij.sh   ← this script
# --------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TEMPLATE_FILE="$REPO_ROOT/config/zellij.zsh"

# --------------------------------------------------
# Homebrew detection (Linuxbrew)
# --------------------------------------------------
check_brew() {
  command -v brew >/dev/null 2>&1 && return 0

  local candidates=(
    "$HOME_DIR/.linuxbrew/bin/brew"
    "/home/linuxbrew/.linuxbrew/bin/brew"
  )

  for brew_bin in "${candidates[@]}"; do
    if [[ -x "$brew_bin" ]]; then
      eval "$("$brew_bin" shellenv)"
      command -v brew >/dev/null 2>&1 && return 0
    fi
  done

  return 1
}

# --------------------------------------------------
# Actions
# --------------------------------------------------
deps() {
  require_user
  log "📦 Checking Homebrew…"
  check_brew || die "Homebrew not available"
  log "✅ Homebrew available"
}

install() {
  require_user
  check_brew || die "Homebrew not available"

  log "🔌 Installing zellij…"

  if brew list zellij >/dev/null 2>&1; then
    brew upgrade zellij
    log "🔄 zellij upgraded"
  else
    brew install zellij
    log "⬇️  zellij installed"
  fi

  command -v zellij >/dev/null 2>&1 || die "zellij not found after install"
}

config() {
  require_user
  command -v zellij >/dev/null 2>&1 || die "Run install first"

  log "⚙️  Writing Zellij config…"
  mkdir -p "$ZELLIJ_CONFIG_DIR"

  cat >"$ZELLIJ_CONFIG_FILE" <<'EOF'
theme "catppuccin-mocha"

themes {
  catppuccin-mocha {
    fg "#cdd6f4"
    bg "#1e1e2e"
    black "#45475a"
    red "#f38ba8"
    green "#a6e3a1"
    yellow "#f9e2af"
    blue "#89b4fa"
    magenta "#f5c2e7"
    cyan "#94e2d5"
    white "#bac2de"
    orange "#fab387"
  }
}

default_layout "compact"
default_mode "normal"

copy_on_select true
copy_clipboard "system"
copy_command "wl-copy"
paste_command "wl-paste --no-newline"
mouse_mode true
EOF

  log "🎨 Zellij theme configured"

  # ---- Zsh config (THIS WAS MISSING) ----
  [[ -f "$TEMPLATE_FILE" ]] || die "Missing template: $TEMPLATE_FILE"

  mkdir -p "$ZSH_CONFIG_DIR"
  cp "$TEMPLATE_FILE" "$ZSH_TARGET_CONFIG"

  log "✅ Installed Zsh config: $ZSH_TARGET_CONFIG"
}

clean() {
  require_user
  log "🧹 Cleaning zellij…"

  rm -f "$ZSH_TARGET_CONFIG"
  rm -rf "$ZELLIJ_CONFIG_DIR"

  if check_brew && brew list zellij >/dev/null 2>&1; then
    brew uninstall zellij
    log "🗑️  zellij uninstalled"
  fi
}

# --------------------------------------------------
# Entry point
# --------------------------------------------------
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
