#!/bin/bash
set -e

MODULE_NAME="git"
CONFIG_FILE="$HOME/.config/glimt/userinfo.config"
ACTION="${1:-all}"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# === Dependencies ===
DEPS=("git")

install_dependencies() {
  echo "🔧 Checking required dependencies..."

  if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
    sudo apt update -y
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
      if ! rpm -q "$dep" &>/dev/null; then
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
}

# === Load user config ===
load_user_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "❌ User info config not found: $CONFIG_FILE"
    echo "💡 Run user-profile.sh first to set name and email."
    exit 1
  fi

  source "$CONFIG_FILE"

  if [[ -z "$name" || -z "$email" ]]; then
    echo "❌ Invalid user info in $CONFIG_FILE"
    exit 1
  fi
}

# === Git Installation ===
install_git_package() {
  echo "📦 Ensuring Git is installed..."

  if ! command -v git &>/dev/null; then
    install_dependencies
  else
    echo "✅ Git is already installed."
  fi
}

# === Git Configuration ===
configure_git() {
  echo "🛠️  Configuring Git..."

  git config --global user.name "$name"
  git config --global user.email "$email"
  git config --global init.defaultBranch main
  git config --global credential.helper store

  git config --global core.editor "nano"
  git config --global pull.rebase false
  git config --global color.ui auto
  git config --global core.autocrlf input

  git config --global alias.st status
  git config --global alias.co checkout
  git config --global alias.br branch
  git config --global alias.cm "commit -m"
  git config --global alias.hist "log --oneline --graph --decorate"

  echo "✅ Git configured for $name <$email>"
}

# === Clean Git Config ===
clean_git() {
  echo "🧹 Removing Git global config..."
  git config --global --unset-all user.name 2>/dev/null || true
  git config --global --unset-all user.email 2>/dev/null || true
  git config --global --remove-section alias 2>/dev/null || true
  git config --global --unset core.editor 2>/dev/null || true
  echo "✅ Git config cleaned"
}

# === Help ===
show_help() {
  echo "Usage: $0 [all|deps|install|config|clean]"
  echo ""
  echo "  all      Install and configure Git"
  echo "  deps     Install required dependencies"
  echo "  install  Only install Git"
  echo "  config   Only configure Git"
  echo "  clean    Remove Git global config"
}

# === Dispatch ===
case "$ACTION" in
  all)
    load_user_config
    install_git_package
    configure_git
    ;;
  deps)
    install_dependencies
    ;;
  install)
    install_git_package
    ;;
  config)
    load_user_config
    configure_git
    ;;
  clean)
    clean_git
    ;;
  *)
    show_help
    ;;
esac
