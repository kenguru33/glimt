#!/bin/bash
set -Euo pipefail
trap 'echo "❌ Script failed at: $BASH_COMMAND (line $LINENO)" >&2' ERR

# === Argument Parsing ===
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
  VERBOSE=true
  shift
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-"$SCRIPT_DIR/modules/debian"}"
CONFIG_DIR="$HOME/.config/glimt"
GIT_CONFIG="$CONFIG_DIR/user-git-info.config"
AVATAR_CONFIG="$CONFIG_DIR/set-user-avatar.config"
mkdir -p "$CONFIG_DIR"

# --- helpers: apt quiet on success, loud on error ---
apt_quiet() {
  # usage: apt_quiet install -y git wget
  if ! sudo apt "$@" >/dev/null; then
    echo "❌ apt $* failed" >&2
    # re-run noisily to surface the real error message
    sudo apt "$@"
    exit 1
  fi
}

# Ensure computer doesn't go to sleep or lock while installing (guard for non-GNOME)
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.screensaver lock-enabled false || true
  gsettings set org.gnome.desktop.session idle-delay 0 || true
fi

# === Ensure git, gum, wget ===
ensure_deps() {
  echo "🔧 Checking for required tools..."

  # If sudo token isn't cached yet, ask now (prevents hidden prompts when stdout is /dev/null)
  sudo -n true 2>/dev/null || sudo -v

  # Noninteractive to avoid tzdata prompts etc.
  export DEBIAN_FRONTEND=noninteractive

  apt_quiet update -y
  apt_quiet install -y git wget

  if ! command -v gum >/dev/null 2>&1; then
    echo "📦 Installing gum..."
    apt_quiet update -y
    apt_quiet install -y gum
  fi
}
ensure_deps

# === Splash Screen ===
clear
cat <<"EOF"

      🌟   ✨
   ✨   G L I M T     🌟
       ✨  The Final Shine for Fresh Installs

EOF

# === Ask for Sudo (kept for your UX; token may already be warm) ===
echo ""
echo "🔐 This setup requires sudo privileges..."
sudo -v
gum style --foreground 10 "✅ Sudo access granted."

# === Load existing config (if any) ===
[[ -f "$GIT_CONFIG" ]] && source "$GIT_CONFIG"
[[ -f "$AVATAR_CONFIG" ]] && source "$AVATAR_CONFIG"

# === Git Config Prompt ===
echo ""
echo "🛠 Git configuration (used for commit identity)"
DEFAULT_NAME="${name:-$(git config --global user.name 2>/dev/null || echo "")}"
DEFAULT_EMAIL="${email:-$(git config --global user.email 2>/dev/null || echo "")}"
DEFAULT_EDITOR="${editor:-nvim}"
DEFAULT_BRANCH="${branch:-main}"
DEFAULT_REBASE="${rebase:-true}"

name=$(gum input --value "$DEFAULT_NAME" --placeholder "Full Name" --prompt "👤 Name: ")
email=$(gum input --value "$DEFAULT_EMAIL" --placeholder "you@example.com" --prompt "📧 Email: ")
editor=$(gum input --value "$DEFAULT_EDITOR" --placeholder "nano/nvim/vim" --prompt "📝 Default editor: ")
branch=$(gum input --value "$DEFAULT_BRANCH" --prompt "🌿 Default branch: ")
if gum confirm "🔄 Use rebase when pulling?"; then
  rebase="true"
else
  rebase="false"
fi

cat >"$GIT_CONFIG" <<EOF
name="$name"
email="$email"
editor="$editor"
branch="$branch"
rebase="$rebase"
EOF
gum style --foreground 10 "✅ Git config saved"

# === Gravatar Config Prompt ===
echo ""
echo "👤 Gravatar email (used to download your profile picture)"
DEFAULT_GRAVATAR_EMAIL="${gravatar_email:-$email}"
gravatar_email=$(gum input --value "$DEFAULT_GRAVATAR_EMAIL" --prompt "📧 Gravatar Email: ")
echo "gravatar_email=\"$gravatar_email\"" >"$AVATAR_CONFIG"
gum style --foreground 10 "✅ Gravatar config saved"

# === Confirm Start ===
echo ""
gum confirm "🚀 Ready to run all Glimt modules?" || {
  echo "❌ Setup cancelled."
  exit 1
}

# === Run All Installers ===
echo ""
gum style --foreground 220 --bold "📦 Installing required modules..."

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "❌ Directory not found: $TARGET_DIR" >&2
  exit 1
fi

# Priority order (must run first, in this order)
PRIORITY_MODULES=(
  "install-gnome-config.sh"
  "install-nerdfonts.sh"
  "install-gnome-terminal-theme.sh"
  "install-blackbox-terminal.sh"
)

# Run priority modules first (if present & executable)
for p in "${PRIORITY_MODULES[@]}"; do
  script="$TARGET_DIR/$p"
  if [[ -x "$script" ]]; then
    if $VERBOSE; then
      echo "▶️  Running (priority): $p"
      "$script" all
      echo "✅ Finished: $p"
    else
      gum spin --spinner dot --title "Running $p..." -- "$script" all >/dev/null
      gum style --foreground 10 "✔️  $p finished"
    fi
  else
    echo "⚠️  Priority module not found or not executable: $script"
  fi
done

# Run remaining modules (excluding the priority ones)
find "$TARGET_DIR" -maxdepth 1 -type f -name "*.sh" -executable \
  | grep -v -E "/(install-gnome-config|install-nerdfonts|install-gnome-terminal-theme|install-blackbox-terminal)\.sh$" \
  | sort \
  | while read -r script; do
      MODULE_NAME="$(basename "$script")"
      if $VERBOSE; then
        echo "▶️  Running: $MODULE_NAME"
        "$script" all
        echo "✅ Finished: $MODULE_NAME"
      else
        gum spin --spinner dot --title "Running $MODULE_NAME..." -- "$script" all >/dev/null
        gum style --foreground 10 "✔️  $MODULE_NAME finished"
      fi
    done

# === Optional Extras ===
EXTRAS_SCRIPT="$SCRIPT_DIR/setup-extras.sh"
if [[ -x "$EXTRAS_SCRIPT" ]]; then
  echo ""
  gum style --foreground 220 --bold "🎛 Installing optional extras..."
  if $VERBOSE; then
    bash "$EXTRAS_SCRIPT" --verbose
  else
    bash "$EXTRAS_SCRIPT" --quiet
  fi
else
  echo "⚠️  Optional extras script not found or not executable: $EXTRAS_SCRIPT"
fi

# === Copy glimt.sh to ~/.local/bin ===
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/glimt.sh" "$HOME/.local/bin/glimt"
chmod +x "$HOME/.local/bin/glimt"

# === Copy autocomplete file (guarded) ===
mkdir -p "$HOME/.zsh/completions"
if [[ -f "$SCRIPT_DIR/modules/debian/config/_glimt" ]]; then
  cp "$SCRIPT_DIR/modules/debian/config/_glimt" "$HOME/.zsh/completions"
else
  echo "⚠️  Zsh completion file not found: $SCRIPT_DIR/modules/debian/config/_glimt"
fi

# Revert to normal idle and lock settings (guard for non-GNOME)
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.screensaver lock-enabled true || true
  gsettings set org.gnome.desktop.session idle-delay 300 || true
fi

# === Done ===
echo ""
gum style --padding "1 4" --margin "1" --align center \
  --foreground 10 --bold \
  "🎉 Glimt setup complete!" "" \
  "$(gum style --foreground 15 'Your Debian Trixie system is now ready to use.')" "" \
  "$(gum style --foreground 220 '🔁 Please reboot to apply all changes.')"
