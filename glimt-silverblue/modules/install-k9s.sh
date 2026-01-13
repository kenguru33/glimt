#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ An error occurred in K9s installer. Exiting." >&2' ERR

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
    die "Do not run this module as root directly."
  fi
}

# --------------------------------------------------
# Resolve repo root (config/ sits next to modules/)
# --------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

CONFIG_TEMPLATE_DIR="$REPO_ROOT/config"
TARGET_CONFIG_DIR="$HOME_DIR/.zsh/config"
TARGET_CONFIG_FILE="$TARGET_CONFIG_DIR/k9s.zsh"

# --------------------------------------------------
# Homebrew detection (Linuxbrew)
# --------------------------------------------------
check_brew() {
  command -v brew >/dev/null 2>&1 && return 0

  local paths=(
    "$HOME_DIR/.linuxbrew/bin/brew"
    "/home/linuxbrew/.linuxbrew/bin/brew"
  )

  for p in "${paths[@]}"; do
    if [[ -x "$p" ]]; then
      eval "$("$p" shellenv)"
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
  log "📦 Checking Homebrew (Linuxbrew)..."

  if ! check_brew; then
    die "Homebrew not found. Install prereqs first."
  fi

  log "✅ Homebrew available"
}

install_k9s() {
  require_user
  check_brew || die "Homebrew not available"

  log "🔧 Installing k9s via Homebrew..."

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

  command -v k9s >/dev/null 2>&1 || die "k9s not found in PATH"

  log "🧠 Installing shell config and theme..."

  # ---- Zsh config ----
  [[ -f "$CONFIG_TEMPLATE_DIR/k9s.zsh" ]] ||
    die "Missing config template: $CONFIG_TEMPLATE_DIR/k9s.zsh"

  mkdir -p "$TARGET_CONFIG_DIR"
  cp "$CONFIG_TEMPLATE_DIR/k9s.zsh" "$TARGET_CONFIG_FILE"
  log "✅ Installed Zsh config: $TARGET_CONFIG_FILE"

  # ---- Completions ----
  mkdir -p "$HOME_DIR/.local/share/bash-completion/completions"
  k9s completion bash >"$HOME_DIR/.local/share/bash-completion/completions/k9s" || true

  mkdir -p "$HOME_DIR/.config/fish/completions"
  k9s completion fish >"$HOME_DIR/.config/fish/completions/k9s.fish" || true

  # ---- Catppuccin theme ----
  local SKIN_DIR="$HOME_DIR/.config/k9s/skins"
  mkdir -p "$SKIN_DIR"

  curl -fsSL \
    https://raw.githubusercontent.com/catppuccin/k9s/main/dist/catppuccin-mocha.yaml \
    -o "$SKIN_DIR/catppuccin-mocha.yaml"

  log "🎨 Catppuccin Mocha installed"

  # ---- config.yaml ----
  mkdir -p "$HOME_DIR/.config/k9s"
  cat >"$HOME_DIR/.config/k9s/config.yaml" <<EOF
k9s:
  ui:
    skin: catppuccin-mocha
EOF

  log "✅ K9s configured"
}

clean_k9s() {
  require_user

  log "🧹 Cleaning K9s..."

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
