#!/bin/bash
set -e

# === Config ===
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
USERNAME="${SUDO_USER:-$USER}"
DEPS=("zsh" "git" "curl" "wget" "unzip")

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# === Step 1: Install system packages and set Zsh as default ===
install_dependencies() {
  echo "🔧 Installing required dependencies..."

  if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
    sudo apt update
    for dep in "${DEPS[@]}"; do
      if ! dpkg -l | grep -qw "$dep"; then
        echo "📦 Installing $dep..."
        sudo apt install -y "$dep"
      else
        echo "✅ $dep is already installed."
      fi
    done
  elif [[ "$ID" == "fedora" ]]; then
    for dep in "${DEPS[@]}"; do
      if ! rpm -q "$dep" > /dev/null 2>&1; then
        echo "📦 Installing $dep..."
        sudo dnf install -y "$dep"
      else
        echo "✅ $dep is already installed."
      fi
    done
  else
    echo "❌ Unsupported OS: $ID"
    exit 1
  fi

  echo "🐚 Setting Zsh as the default shell for $USERNAME..."
  ZSH_PATH="$(command -v zsh)"
  sudo chsh -s "$ZSH_PATH" "$USERNAME"
  echo "✅ Default shell set to Zsh. Please log out and back in."
}

# === Step 2: Install Oh My Zsh and Starship ===
install_zsh() {
  echo "🧠 Installing Oh My Zsh..."

  TIMESTAMP=$(date +%Y%m%d%H%M%S)

  [[ -d "$HOME/.oh-my-zsh" ]] && mv "$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh.bak.$TIMESTAMP"
  [[ -f "$HOME/.zshrc" ]] && mv "$HOME/.zshrc" "$HOME/.zshrc.bak.$TIMESTAMP"

  export RUNZSH=no
  export CHSH=no
  export KEEP_ZSHRC=yes
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

  echo "🚀 Installing Starship prompt..."
  curl -sS https://starship.rs/install.sh | sh -s -- -y
}

# === Step 3: Configure plugins, theme, starship ===
configure_zsh() {
  echo "🔌 Installing Zsh plugins..."
  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  git clone https://github.com/zsh-users/zsh-completions "$ZSH_CUSTOM/plugins/zsh-completions"

  echo "✨ Updating .zshrc..."
  sed -i 's/^plugins=.*/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-completions)/' ~/.zshrc || true
  sed -i 's/^ZSH_THEME=.*/ZSH_THEME="robbyrussell"/' ~/.zshrc || true

  {
    echo 'fpath+=~/.oh-my-zsh/custom/plugins/zsh-completions/src'
    echo 'autoload -Uz compinit && compinit'
  } >> ~/.zshrc

  echo 'eval "$(starship init zsh)"' >> ~/.zshrc
  echo "✅ Zsh configuration complete."
}

# === Step 4: Clean everything ===
cleanup() {
  echo "🧹 Cleaning up Zsh and related config..."

  rm -rf ~/.oh-my-zsh ~/.zshrc ~/.zshenv ~/.zprofile ~/.zsh ~/.zcompdump* ~/.config/starship.toml

  if command -v bash >/dev/null; then
    sudo chsh -s "$(command -v bash)" "$USERNAME"
    echo "✅ Shell reverted to Bash. Please log out and back in."
  fi

  if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
    sudo apt remove --purge -y zsh
    sudo apt autoremove -y
  elif [[ "$ID" == "fedora" ]]; then
    sudo dnf remove -y zsh
    sudo dnf autoremove -y || true
  fi

  sudo rm -f /usr/local/bin/starship
  echo "✅ Cleanup complete."
}

# === Help ===
show_help() {
  echo "Usage: $0 [all|deps|install|config|clean]"
  echo ""
  echo "  all       Run full installation process (deps + install + config)"
  echo "  deps      Install system packages and set Zsh as shell"
  echo "  install   Install Oh My Zsh and Starship"
  echo "  config    Configure plugins and Starship in .zshrc"
  echo "  clean     Remove all Zsh-related config and reset shell"
}

# === Entry Point ===
case "$1" in
  all)
    install_dependencies
    install_zsh
    configure_zsh
    ;;
  deps)
    install_dependencies
    ;;
  install)
    install_zsh
    ;;
  config)
    configure_zsh
    ;;
  clean)
    cleanup
    ;;
  *)
    show_help
    ;;
esac

