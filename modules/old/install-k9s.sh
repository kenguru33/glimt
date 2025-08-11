#!/bin/bash
set -e
trap 'echo "❌ An error occurred in K9s installer. Exiting." >&2' ERR

MODULE_NAME="k9s"
K9S_VERSION="v0.32.4"
ARCH="$(uname -m)"
ACTION="${1:-all}"

# === Normalize Architecture ===
normalize_arch() {
  case "$ARCH" in
    x86_64) echo "amd64" ;;
    aarch64 | arm64) echo "arm64" ;;
    *)
      echo "❌ Unsupported architecture: $ARCH"
      exit 1
      ;;
  esac
}

# === Ensure ~/.local/bin is in PATH in .zshrc ===
ensure_local_bin_path() {
  if ! grep -q 'export PATH=.*\.local/bin' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
    echo "✅ Added ~/.local/bin to PATH in ~/.zshrc"
  fi
}

# === Ensure Oh My Zsh completions are loaded ===
ensure_zsh_completions_fpath() {
  local zshrc="$HOME/.zshrc"
  local fpath_line='fpath+=("$HOME/.oh-my-zsh/completions")'

  if ! grep -qF "$fpath_line" "$zshrc"; then
    echo "🔧 Adding Oh My Zsh completion path to ~/.zshrc..."

    if grep -q 'compinit' "$zshrc"; then
      sed -i "/compinit/i\\$fpath_line" "$zshrc"
    else
      echo "$fpath_line" >> "$zshrc"
    fi

    echo "✅ Added Zsh completion fpath for k9s"
  fi
}

# === Step: deps ===
install_dependencies() {
  echo "ℹ️  No dependencies needed for $MODULE_NAME"
}

# === Step: install ===
install_k9s() {
  echo "🔧 Installing K9s $K9S_VERSION to ~/.local/bin..."

  local norm_arch url
  norm_arch="$(normalize_arch)"
  url="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${norm_arch}.tar.gz"

  mkdir -p "$HOME/.local/bin"
  curl -fsSL "$url" -o /tmp/k9s.tar.gz
  tar -xzf /tmp/k9s.tar.gz -C /tmp

  mv /tmp/k9s "$HOME/.local/bin/k9s"
  chmod +x "$HOME/.local/bin/k9s"
  rm -f /tmp/k9s.tar.gz

  echo "✅ K9s installed at ~/.local/bin/k9s"
  ensure_local_bin_path
}

# === Step: config ===
config_k9s() {
  echo "🧠 Installing K9s shell completions and Mocha theme..."

  if [[ ! -x "$HOME/.local/bin/k9s" ]]; then
    echo "⚠️  K9s binary not found. Run 'install' first."
    exit 1
  fi

  # Bash
  mkdir -p "$HOME/.local/share/bash-completion/completions"
  "$HOME/.local/bin/k9s" completion bash > "$HOME/.local/share/bash-completion/completions/k9s"

  # Zsh (Oh My Zsh)
  local ZSH_COMPLETION_DIR="$HOME/.oh-my-zsh/completions"
  mkdir -p "$ZSH_COMPLETION_DIR"
  "$HOME/.local/bin/k9s" completion zsh > "$ZSH_COMPLETION_DIR/_k9s"
  ensure_zsh_completions_fpath

  # Fish
  mkdir -p "$HOME/.config/fish/completions"
  "$HOME/.local/bin/k9s" completion fish > "$HOME/.config/fish/completions/k9s.fish"

  # Theme (Mocha only)
  local SKIN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/k9s/skins"
  mkdir -p "$SKIN_DIR"
  curl -fsSL https://raw.githubusercontent.com/catppuccin/k9s/main/dist/catppuccin-mocha.yaml \
    -o "$SKIN_DIR/catppuccin-mocha.yaml"
  echo "✅ Theme saved to $SKIN_DIR/catppuccin-mocha.yaml"

  # Config.yaml
  local CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/k9s/config.yaml"
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cat <<EOF > "$CONFIG_FILE"
k9s:
  ui:
    skin: catppuccin-mocha
EOF

  echo "✅ config.yaml written with Catppuccin Mocha"
}

# === Step: clean ===
clean_k9s() {
  echo "🧹 Removing K9s and related files..."

  rm -f "$HOME/.local/bin/k9s"
  rm -f "$HOME/.local/share/bash-completion/completions/k9s"
  rm -f "$HOME/.oh-my-zsh/completions/_k9s"
  rm -f "$HOME/.config/fish/completions/k9s.fish"
  rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/k9s/skins"
  rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/k9s/config.yaml"

  echo "✅ All K9s files removed."
}

# === Entry Point ===
case "$ACTION" in
  deps)
    install_dependencies
    ;;
  install)
    install_k9s
    ;;
  config)
    config_k9s
    ;;
  clean)
    clean_k9s
    ;;
  all)
    install_k9s
    config_k9s
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    ;;
esac
