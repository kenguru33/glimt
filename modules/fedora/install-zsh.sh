#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="zsh"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

PLUGIN_DIR="$HOME_DIR/.zsh/plugins"
CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSHRC_FILE="$HOME_DIR/.zshrc"
LOCAL_BIN="$HOME_DIR/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC_TEMPLATE="$SCRIPT_DIR/config/zshrc"
# Templates in config/ deployed to ~/.zsh/config/<name>.zsh (and removed by clean)
CONFIG_TEMPLATES=(autosuggestions syntax-highlighting greeting)

declare -A PLUGINS=(
  ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
  ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
)

# === Step: deps ===
deps() {
  echo "Installing Zsh dependencies..."
  dnf_ensure zsh git

  echo "Ensuring $LOCAL_BIN exists..."
  run_as_user mkdir -p "$LOCAL_BIN"
}

# === Step: install ===
install() {
  echo "Installing or updating Zsh plugins..."
  run_as_user mkdir -p "$PLUGIN_DIR"

  for name in "${!PLUGINS[@]}"; do
    repo="${PLUGINS[$name]}"
    dir="$PLUGIN_DIR/$name"

    if [[ -d "$dir/.git" ]]; then
      echo "Updating $name..."
      run_as_user git -C "$dir" pull --quiet --rebase
      echo "Updated $name"
    else
      echo "⬇️  Installing $name..."
      rm -rf "$dir"
      run_as_user git clone --depth=1 "$repo" "$dir"
      echo "Installed $name"
    fi
  done

  echo "Ensuring Zsh is default shell for $REAL_USER..."
  if [[ "$(getent passwd "$REAL_USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
    sudo chsh -s "$(command -v zsh)" "$REAL_USER"
    echo "Default shell set to Zsh"
  else
    echo "⏭️  Zsh already default shell"
  fi
}

# === Step: config ===
config() {
  echo "Installing Zsh plugin configs..."
  for name in "${CONFIG_TEMPLATES[@]}"; do
    deploy_config "$SCRIPT_DIR/config/$name.zsh" "$CONFIG_DIR/$name.zsh"
  done

  echo "Installing .zshrc template..."
  deploy_config "$ZSHRC_TEMPLATE" "$ZSHRC_FILE"
  echo "Installed new .zshrc"
}

# === Step: clean ===
clean() {
  echo "Cleaning Zsh setup..."

  # Only remove what this module created — other modules (fzf, gh, kubectl,
  # eza, ...) also keep their plugins and configs under ~/.zsh.
  echo "Removing plugins from $PLUGIN_DIR"
  for name in "${!PLUGINS[@]}"; do
    rm -rf "${PLUGIN_DIR:?}/$name"
  done

  echo "Removing Zsh config files"
  for name in "${CONFIG_TEMPLATES[@]}"; do
    rm -f "$CONFIG_DIR/$name.zsh"
  done

  echo "Removing .zshrc"
  rm -f "$ZSHRC_FILE"

  # Changing the login shell back is left to the user (we can't know which
  # shell they want), but make sure they know zsh is still set.
  local login_shell
  login_shell="$(getent passwd "$REAL_USER" | cut -d: -f7)"
  if [[ "$(basename "${login_shell:-}")" == "zsh" ]]; then
    warn "zsh is still the login shell for $REAL_USER ($login_shell)."
    warn "Change it back with: sudo chsh -s /bin/bash $REAL_USER"
  fi

  echo "Clean complete."
}

# === Entry Point ===
case "$ACTION" in
  all)    deps; install; config ;;
  deps)   deps ;;
  install) install ;;
  config) config ;;
  clean)  clean ;;
  *)
    echo "[$MODULE_NAME] unknown action: $ACTION" >&2
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

