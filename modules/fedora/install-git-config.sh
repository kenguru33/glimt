#!/bin/bash
set -e
trap 'echo "❌ Git config setup failed. Exiting." >&2' ERR

MODULE_NAME="git-config"
ACTION="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_DIR="$HOME/.config/glimt"
CONFIG_FILE="$CONFIG_DIR/user-git-info.config"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_TARGET_FILE="$ZSH_CONFIG_DIR/git.zsh"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins/git"
FALLBACK_COMPLETION="$PLUGIN_DIR/git-completion.zsh"
TEMPLATE_FILE="$SCRIPT_DIR/config/git.zsh"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# === Dependencies ===
DEPS=(git curl)

install_dependencies() {
  echo "🔧 Installing required dependencies..."
  if [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* ]]; then
    sudo dnf makecache -y
    for pkg in "${DEPS[@]}"; do
      if ! rpm -q "$pkg" &>/dev/null; then
        echo "📦 Installing $pkg..."
        sudo dnf install -y "$pkg"
      fi
    done
  else
    echo "❌ Unsupported OS: $ID. Only Fedora-based systems are supported."
    exit 1
  fi
}

# === Prompt user for config using gum ===
prompt_git_config() {
  echo "🔧 Prompting for Git user info..."
  mkdir -p "$CONFIG_DIR"

  while true; do
    name=$(gum input --prompt "📝 Enter your full name: " --placeholder "John Doe")
    [[ -z "$name" ]] && gum style --foreground 1 "❌ Name cannot be empty." && continue
    break
  done

  while true; do
    email=$(gum input --prompt "📧 Enter your email address: " --placeholder "john@example.com")
    if [[ -z "$email" ]]; then
      gum style --foreground 1 "❌ Email cannot be empty."
    elif [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
      break
    else
      gum style --foreground 1 "❌ Invalid email format."
    fi
  done

  editor=$(gum input --prompt "🖊️  Default Git editor: " --placeholder "nvim" --value "nvim")
  branch=$(gum input --prompt "🌿 Default Git branch: " --placeholder "main" --value "main")

  rebase=false
  gum confirm --prompt "🔁 Use rebase when pulling? (press space to select)" && rebase=true

  gum format --theme=dark <<<"# 🧾 Review Git Configuration

✅ Name: **$name**  
✅ Email: **$email**  
✅ Editor: **$editor**  
✅ Default Branch: **$branch**  
✅ Pull Rebase: **$rebase**"

  if gum confirm "💾 Save this configuration?"; then
    {
      echo "name=\"$name\""
      echo "email=\"$email\""
      echo "editor=\"$editor\""
      echo "branch=\"$branch\""
      echo "rebase=\"$rebase\""
    } > "$CONFIG_FILE"
    echo "✅ Saved Git config to $CONFIG_FILE"
  else
    gum style --foreground 1 "❌ Aborted by user."
    exit 1
  fi
}

load_git_config() {
  if [[ "$ACTION" == "reconfigure" || ! -f "$CONFIG_FILE" ]]; then
    prompt_git_config
  fi

  source "$CONFIG_FILE"

  if [[ -z "${name+x}" || -z "${email+x}" || -z "${editor+x}" || -z "${branch+x}" || -z "${rebase+x}" ]]; then
    gum style --foreground 1 "❌ Config incomplete. Re-prompting..."
    prompt_git_config
    source "$CONFIG_FILE"
  fi
}

configure_git() {
  echo "🛠️  Applying Git configuration..."

  sudo -u "$REAL_USER" git config --global user.name "$name"
  sudo -u "$REAL_USER" git config --global user.email "$email"
  sudo -u "$REAL_USER" git config --global init.defaultBranch "$branch"
  sudo -u "$REAL_USER" git config --global credential.helper store
  sudo -u "$REAL_USER" git config --global core.editor "$editor"
  sudo -u "$REAL_USER" git config --global pull.rebase "$rebase"
  sudo -u "$REAL_USER" git config --global color.ui auto
  sudo -u "$REAL_USER" git config --global core.autocrlf input

  sudo -u "$REAL_USER" git config --global alias.st status
  sudo -u "$REAL_USER" git config --global alias.co checkout
  sudo -u "$REAL_USER" git config --global alias.br branch
  sudo -u "$REAL_USER" git config --global alias.cm "commit -m"
  sudo -u "$REAL_USER" git config --global alias.hist "log --oneline --graph --decorate"

  echo "✅ Git configured for $name <$email>"
}

install_git_completion_zsh() {
  if [[ ! -f "$FALLBACK_COMPLETION" ]]; then
    echo "📥 Downloading git-completion.zsh fallback..."
    mkdir -p "$PLUGIN_DIR"
    curl -fsSL https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.zsh \
      -o "$FALLBACK_COMPLETION"
    chown -R "$REAL_USER:$REAL_USER" "$PLUGIN_DIR"
    echo "✅ Installed fallback: $FALLBACK_COMPLETION"
  else
    echo "⏭️  git-completion.zsh already present"
  fi
}

config_git_shell() {
  echo "📄 Installing config/git.zsh from template..."
  mkdir -p "$ZSH_CONFIG_DIR"
  cp "$TEMPLATE_FILE" "$ZSH_TARGET_FILE"
  chown "$REAL_USER:$REAL_USER" "$ZSH_TARGET_FILE"
  echo "✅ Installed $ZSH_TARGET_FILE"
}

clean_git_config() {
  echo "🧹 Cleaning Git global config..."

  sudo -u "$REAL_USER" git config --global --unset-all user.name 2>/dev/null || true
  sudo -u "$REAL_USER" git config --global --unset-all user.email 2>/dev/null || true
  sudo -u "$REAL_USER" git config --global --remove-section alias 2>/dev/null || true
  sudo -u "$REAL_USER" git config --global --unset core.editor 2>/dev/null || true

  echo "🧼 Removing Zsh config file and plugin..."
  rm -f "$ZSH_TARGET_FILE"
  rm -rf "$PLUGIN_DIR"
  rm -f "$CONFIG_FILE"

  echo "✅ Git config cleaned"
}

show_help() {
  echo "Usage: $0 [all|deps|config|reconfigure|clean]"
  echo ""
  echo "  all          Install deps, configure Git, completions, shell integration"
  echo "  deps         Install required dependencies (git, gum)"
  echo "  config       Configure Git (if config exists or prompts if missing)"
  echo "  reconfigure  Prompt again and overwrite Git config"
  echo "  clean        Remove Git config, completions, and shell integration"
}

# === Entry Point ===
case "$ACTION" in
  all)
    install_dependencies
    load_git_config
    configure_git
    install_git_completion_zsh
    config_git_shell
    ;;
  deps)
    install_dependencies
    ;;
  config)
    load_git_config
    configure_git
    install_git_completion_zsh
    config_git_shell
    ;;
  reconfigure)
    ACTION="reconfigure"
    load_git_config
    configure_git
    install_git_completion_zsh
    config_git_shell
    ;;
  clean)
    clean_git_config
    ;;
  *)
    show_help
    ;;
esac

