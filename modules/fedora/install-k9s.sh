#!/bin/bash
set -e
trap 'echo "❌ An error occurred in K9s installer. Exiting." >&2' ERR

MODULE_NAME="k9s"
K9S_VERSION="v0.32.4"
ARCH="$(uname -m)"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
CONFIG_TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config"
TARGET_CONFIG_DIR="$HOME_DIR/.zsh/config"
TARGET_CONFIG_FILE="$TARGET_CONFIG_DIR/k9s.zsh"

# === OS Check (Fedora only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This module supports Fedora/RHEL-based systems only."
  exit 1
fi

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
  if ! grep -q 'export PATH=.*\.local/bin' "$HOME_DIR/.zshrc" 2>/dev/null; then
    sudo -u "$REAL_USER" sh -c "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> '$HOME_DIR/.zshrc'"
    echo "✅ Added ~/.local/bin to PATH in ~/.zshrc"
  fi
}

# === Step: deps ===
install_dependencies() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y curl tar gzip
}

# === Step: install ===
install_k9s() {
  echo "🔧 Installing K9s $K9S_VERSION to ~/.local/bin..."

  local norm_arch url
  norm_arch="$(normalize_arch)"
  url="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${norm_arch}.tar.gz"

  sudo -u "$REAL_USER" mkdir -p "$HOME_DIR/.local/bin"
  TMP_TAR="$(mktemp)"
  TMP_DIR="$(mktemp -d)"
  
  curl -fsSL "$url" -o "$TMP_TAR"
  sudo -u "$REAL_USER" tar -xzf "$TMP_TAR" -C "$TMP_DIR"

  sudo -u "$REAL_USER" mv "$TMP_DIR/k9s" "$HOME_DIR/.local/bin/k9s"
  sudo -u "$REAL_USER" chmod +x "$HOME_DIR/.local/bin/k9s"
  rm -f "$TMP_TAR"
  rm -rf "$TMP_DIR"

  echo "✅ K9s installed at ~/.local/bin/k9s"
  ensure_local_bin_path
}

# === Step: config ===
config_k9s() {
  echo "🧠 Installing K9s config and theme..."

  if [[ ! -x "$HOME_DIR/.local/bin/k9s" ]]; then
    echo "⚠️  K9s binary not found. Run 'install' first."
    exit 1
  fi

  # Shell completion loader config
  sudo -u "$REAL_USER" mkdir -p "$TARGET_CONFIG_DIR"
  if [[ -f "$CONFIG_TEMPLATE_DIR/k9s.zsh" ]]; then
    sudo -u "$REAL_USER" cp "$CONFIG_TEMPLATE_DIR/k9s.zsh" "$TARGET_CONFIG_FILE"
    chown "$REAL_USER:$REAL_USER" "$TARGET_CONFIG_FILE"
    echo "✅ Installed Zsh completion config: $TARGET_CONFIG_FILE"
  fi

  # Bash completion
  sudo -u "$REAL_USER" mkdir -p "$HOME_DIR/.local/share/bash-completion/completions"
  sudo -u "$REAL_USER" "$HOME_DIR/.local/bin/k9s" completion bash > "$HOME_DIR/.local/share/bash-completion/completions/k9s" || true

  # Fish completion
  sudo -u "$REAL_USER" mkdir -p "$HOME_DIR/.config/fish/completions"
  sudo -u "$REAL_USER" "$HOME_DIR/.local/bin/k9s" completion fish > "$HOME_DIR/.config/fish/completions/k9s.fish" || true

  # Catppuccin theme
  local SKIN_DIR="$HOME_DIR/.config/k9s/skins"
  sudo -u "$REAL_USER" mkdir -p "$SKIN_DIR"
  sudo -u "$REAL_USER" curl -fsSL https://raw.githubusercontent.com/catppuccin/k9s/main/dist/catppuccin-mocha.yaml \
    -o "$SKIN_DIR/catppuccin-mocha.yaml"
  echo "✅ Theme saved to $SKIN_DIR/catppuccin-mocha.yaml"

  # config.yaml
  local CONFIG_FILE="$HOME_DIR/.config/k9s/config.yaml"
  sudo -u "$REAL_USER" mkdir -p "$(dirname "$CONFIG_FILE")"
  sudo -u "$REAL_USER" cat <<EOF > "$CONFIG_FILE"
k9s:
  ui:
    skin: catppuccin-mocha
EOF

  chown -R "$REAL_USER:$REAL_USER" "$HOME_DIR/.config/k9s"
  echo "✅ config.yaml written with Catppuccin Mocha"
}

# === Step: clean ===
clean_k9s() {
  echo "🧹 Removing K9s and related files..."

  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.local/bin/k9s"
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.local/share/bash-completion/completions/k9s"
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/fish/completions/k9s.fish"
  sudo -u "$REAL_USER" rm -rf "$HOME_DIR/.config/k9s"
  sudo -u "$REAL_USER" rm -f "$TARGET_CONFIG_FILE"

  echo "✅ All K9s files removed."
}

# === Entry Point ===
case "$ACTION" in
  deps)    install_dependencies ;;
  install) install_k9s ;;
  config)  config_k9s ;;
  clean)   clean_k9s ;;
  all)     install_dependencies; install_k9s; config_k9s ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac


