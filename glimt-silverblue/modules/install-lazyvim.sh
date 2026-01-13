#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ LazyVim module failed." >&2' ERR

MODULE_NAME="lazyvim"
ACTION="${1:-all}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

HOME_DIR="$HOME"

NVIM_DIRS=(
  "$HOME_DIR/.config/nvim"
  "$HOME_DIR/.local/share/nvim"
  "$HOME_DIR/.local/state/nvim"
  "$HOME_DIR/.cache/nvim"
)

# --------------------------------------------------
# Homebrew discovery / bootstrap
# --------------------------------------------------
detect_brew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  local candidates=(
    "$HOME_DIR/.linuxbrew/bin/brew"
    "/home/linuxbrew/.linuxbrew/bin/brew"
  )

  for brew_path in "${candidates[@]}"; do
    if [[ -x "$brew_path" ]]; then
      export PATH="$(dirname "$brew_path"):$PATH"
      return 0
    fi
  done

  return 1
}

install_brew() {
  echo "🍺 Homebrew not found – installing (user-local)…"
  NONINTERACTIVE=1 \
    /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  detect_brew || {
    echo "❌ Homebrew install failed"
    exit 1
  }
}

ensure_brew() {
  if ! detect_brew; then
    install_brew
  fi

  echo "✅ Homebrew ready: $(brew --version | head -n1)"
}

# --------------------------------------------------
# deps: install neovim via brew
# --------------------------------------------------
deps() {
  ensure_brew

  echo "🍺 Installing Neovim via Homebrew…"
  if brew list neovim &>/dev/null; then
    echo "✅ Neovim already installed."
  else
    brew install neovim
    echo "✅ Neovim installed."
  fi
}

# --------------------------------------------------
# install: LazyVim
# --------------------------------------------------
install_lazyvim() {
  echo "📁 Backing up existing Neovim data…"

  for dir in "${NVIM_DIRS[@]}"; do
    if [[ -e "$dir" ]]; then
      backup="${dir}.bak-${TIMESTAMP}"
      mv "$dir" "$backup"
      echo "🔄 Moved $dir → $backup"
    fi
  done

  echo "📥 Cloning LazyVim starter…"
  git clone https://github.com/LazyVim/starter "$HOME_DIR/.config/nvim"
  rm -rf "$HOME_DIR/.config/nvim/.git"

  echo "✅ LazyVim installed."
  echo "🚀 Start Neovim with 'nvim' and run :Lazy sync"
}

# --------------------------------------------------
# config
# --------------------------------------------------
config_lazyvim() {
  echo "🎨 Adding Catppuccin theme plugin…"

  PLUGIN_DIR="$HOME_DIR/.config/nvim/lua/plugins"
  mkdir -p "$PLUGIN_DIR"

  cat >"$PLUGIN_DIR/catppuccin.lua" <<'EOF'
return {
  "catppuccin/nvim",
  name = "catppuccin",
  priority = 1000,
  config = function()
    vim.cmd.colorscheme("catppuccin")
  end,
}
EOF

  echo "✅ Catppuccin configured."
}

# --------------------------------------------------
# clean
# --------------------------------------------------
clean_lazyvim() {
  echo "🧹 Removing LazyVim configuration…"

  for dir in "${NVIM_DIRS[@]}"; do
    [[ -e "$dir" ]] && rm -rf "$dir" && echo "🗑️  Removed $dir"
  done

  ensure_brew
  read -rp "Uninstall Neovim (brew)? [y/N]: " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    brew uninstall neovim || true
    echo "✅ Neovim removed."
  fi
}

# --------------------------------------------------
# restore
# --------------------------------------------------
restore_backup() {
  echo "📂 Restoring latest backups…"

  for dir in "${NVIM_DIRS[@]}"; do
    latest_backup="$(ls -d "${dir}.bak-"* 2>/dev/null | sort | tail -n1 || true)"
    if [[ -n "$latest_backup" ]]; then
      echo "🔁 Restoring $latest_backup → $dir"
      rm -rf "$dir"
      mv "$latest_backup" "$dir"
    else
      echo "⚠️ No backup found for $dir"
    fi
  done

  echo "✅ Restore complete."
}

# --------------------------------------------------
# Dispatcher
# --------------------------------------------------
case "$ACTION" in
deps)
  deps
  ;;
install)
  install_lazyvim
  ;;
config)
  config_lazyvim
  ;;
clean)
  clean_lazyvim
  ;;
restore)
  restore_backup
  ;;
all)
  deps
  install_lazyvim
  config_lazyvim
  ;;
*)
  echo "Usage: $0 [deps|install|config|clean|restore|all]"
  exit 1
  ;;
esac
