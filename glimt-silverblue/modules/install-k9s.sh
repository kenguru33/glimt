#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [k9s] installer failed at line $LINENO" >&2' ERR

MODULE_NAME="k9s"
ACTION="${1:-all}"

# --------------------------------------------------
# User context (Silverblue-safe)
# --------------------------------------------------
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

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
# ├── config/k9s.zsh
# └── modules/install-k9s.sh   ← this script
# --------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CONFIG_TEMPLATE_DIR="$REPO_ROOT/config"
TARGET_CONFIG_DIR="$HOME_DIR/.zsh/config"
TARGET_CONFIG_FILE="$TARGET_CONFIG_DIR/k9s.zsh"

# --------------------------------------------------
# Homebrew (Linuxbrew) detection
# --------------------------------------------------
check_brew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

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
install_dependencies() {
  require_user
  log "📦 Checking Homebrew…"

  check_brew || die "Homebrew not found. Run prereq module first."
  log "✅ Homebrew available"
}

install_k9s() {
  require_user
  check_brew || die "Homebrew not available"

  log "🔧 Installing k9s…"

  if brew list k9s >/dev/null 2>&1; then
    brew upgrade k9s
    log "🔄 k9s upgraded"
  else
    brew install k9s
    log "⬇️  k9s installed"
  fi
}

config_k9s() {
  require_user
  check_brew || die "Homebrew not available"

  command -v k9s >/dev/null 2>&1 || die "k9s not in PATH (run install first)"

  log "🧠 Installing k9s shell config…"

  # ---- Zsh config (THIS was missing before) ----
  [[ -f "$CONFIG_TEMPLATE_DIR/k9s.zsh" ]] ||
    die "Missing config template: $CONFIG_TEMPLATE_DIR/k9s.zsh"

  mkdir -p "$TARGET_CONFIG_DIR"
  cp "$CONFIG_TEMPLATE_DIR/k9s.zsh" "$TARGET_CONFIG_FILE"

  log "✅ Installed: $TARGET_CONFIG_FILE"

  # ---- Completions ----
  mkdir -p "$HOME_DIR/.local/share/bash-completion/completions"
  k9s completion bash \
    >"$HOME_DIR/.local/share/bash-completion/completions/k9s" || true

  mkdir -p "$HOME_DIR/.config/fish/completions"
  k9s completion fish \
    >"$HOME_DIR/.config/fish/completions/k9s.fish" || true

  # ---- Catppuccin theme ----
  local SKIN_DIR="$HOME_DIR/.config/k9s/skins"
  mkdir -p "$SKIN_DIR"

  curl -fsSL \
    https://raw.githubusercontent.com/catppuccin/k9s/main/dist/catppuccin-mocha.yaml \
    -o "$SKIN_DIR/catppuccin-mocha.yaml"

  # ---- config.yaml ----
  mkdir -p "$HOME_DIR/.config/k9s"
  cat >"$HOME_DIR/.config/k9s/config.yaml" <<EOF
k9s:
  ui:
    skin: catppuccin-mocha
EOF

  log "🎨 Catppuccin Mocha configured"
}

clean_k9s() {
  require_user
  log "🧹 Removing k9s…"

  rm -f "$TARGET_CONFIG_FILE"
  rm -rf "$HOME_DIR/.config/k9s"
  rm -f "$HOME_DIR/.local/share/bash-completion/completions/k9s"
  rm -f "$HOME_DIR/.config/fish/completions/k9s.fish"

  if check_brew && brew list k9s >/dev/null 2>&1; then
    brew uninstall k9s
    log "🗑️  k9s uninstalled"
  fi
}

# --------------------------------------------------
# Entry point
# --------------------------------------------------
case "$ACTION" in
deps) install_dependencies ;;
install) install_k9s ;;
config) config_k9s ;;
clean) clean_k9s ;;
all)
  install_dependencies
  install_k9s
  config_k9s
  ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
