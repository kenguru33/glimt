#!/bin/bash
set -Euo pipefail
trap 'echo "Error: setup failed at line $LINENO: $BASH_COMMAND" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# === macOS → delegate to setup-macos.sh (before parsing, so flags pass through) ===
if [[ "$(uname -s)" == "Darwin" ]]; then
  exec "$SCRIPT_DIR/setup-macos.sh" "$@"
fi

# === Argument Parsing ===
# Default: a single progress bar, module output goes to log files.
# -v/--verbose: show every module's full output instead.
VERBOSE=false
MODULES_DIR=""
for arg in "$@"; do
  case "$arg" in
  -v | --verbose) VERBOSE=true ;;
  -h | --help)
    echo "Usage: $(basename "$0") [-v|--verbose] [modules-dir]"
    exit 0
    ;;
  -*)
    echo "Unknown option: $arg" >&2
    exit 1
    ;;
  *) MODULES_DIR="$arg" ;;
  esac
done

source "$SCRIPT_DIR/setup-lib.sh"

CONFIG_DIR="$HOME/.config/glimt"
GIT_CONFIG="$CONFIG_DIR/user-git-info.config"
AVATAR_CONFIG="$CONFIG_DIR/set-user-avatar.config"
mkdir -p "$CONFIG_DIR"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
  OS_ID_LIKE="${ID_LIKE:-}"
else
  echo "Error: cannot detect OS (/etc/os-release missing)" >&2
  exit 1
fi

if [[ "$OS_ID" != "fedora" && "$OS_ID_LIKE" != *"fedora"* && "$OS_ID" != "rhel" ]]; then
  echo "Error: unsupported OS '$OS_ID' (glimt requires Fedora or RHEL)" >&2
  exit 1
fi

MODULES_DIR="${MODULES_DIR:-"$SCRIPT_DIR/modules/fedora"}"
PKG_MANAGER="dnf"

TARGET_DIR="$MODULES_DIR"

# --- helpers: package manager quiet on success, loud on error ---
pkg_quiet() {
  # usage: pkg_quiet install -y git wget
  if ! sudo dnf "$@" -q >/dev/null 2>&1; then
    echo "Error: dnf $* failed" >&2
    sudo dnf "$@"
    exit 1
  fi
}

# === Ask for sudo once, up front; kept alive for the whole run ===
glimt_require_sudo

# Ensure computer doesn't go to sleep or lock while installing (guard for non-GNOME)
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.screensaver lock-enabled false || true
  gsettings set org.gnome.desktop.session idle-delay 0 || true
fi

# === Ensure git, gum, wget ===
ensure_deps() {
  # Refresh metadata once here — modules must NOT call makecache individually
  pkg_quiet makecache -y
  pkg_quiet install -y git wget
  if ! command -v gum >/dev/null 2>&1; then
    pkg_quiet makecache -y
    if ! pkg_quiet install -y gum 2>/dev/null; then
      if command -v go >/dev/null 2>&1; then
        go install github.com/charmbracelet/gum@v0.14.3
      else
        echo "Error: gum is not in the repos; install gum or Go and retry" >&2
      fi
    fi
  fi
}
ensure_deps

# === Header ===
glimt_banner "Fedora post-install setup"

# === Load existing config (if any) ===
[[ -f "$GIT_CONFIG" ]] && source "$GIT_CONFIG"
[[ -f "$AVATAR_CONFIG" ]] && source "$AVATAR_CONFIG"

# === Git Config Prompt ===
glimt_section "Git"
DEFAULT_NAME="${name:-$(git config --global user.name 2>/dev/null || echo "")}"
DEFAULT_EMAIL="${email:-$(git config --global user.email 2>/dev/null || echo "")}"
DEFAULT_EDITOR="${editor:-nvim}"
DEFAULT_BRANCH="${branch:-main}"
DEFAULT_REBASE="${rebase:-true}"

name=$(gum input --value "$DEFAULT_NAME" --placeholder "Full Name" --prompt "Name: ")
email=$(gum input --value "$DEFAULT_EMAIL" --placeholder "you@example.com" --prompt "Email: ")
editor=$(gum input --value "$DEFAULT_EDITOR" --placeholder "nano/nvim/vim" --prompt "Editor: ")
branch=$(gum input --value "$DEFAULT_BRANCH" --prompt "Default branch: ")
if gum confirm "Rebase when pulling?"; then
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

# === Gravatar Config Prompt ===
glimt_section "Gravatar"
DEFAULT_GRAVATAR_EMAIL="${gravatar_email:-$email}"
gravatar_email=$(gum input --value "$DEFAULT_GRAVATAR_EMAIL" --prompt "Email: ")
echo "gravatar_email=\"$gravatar_email\"" >"$AVATAR_CONFIG"

# === Confirm Start ===
echo ""
gum confirm "Start setup?" || {
  echo "Setup cancelled."
  exit 1
}

# === Run All Installers ===
glimt_section "Core modules"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: directory not found: $TARGET_DIR" >&2
  exit 1
fi

# Priority order (must run first, in this order)
PRIORITY_MODULES=(
  "install-gnome-config.sh"
  "install-nerdfonts.sh"
  "install-gnome-terminal-theme.sh"
)

# Build the full run list up front so the progress bar knows the total
RUN_LIST=()
for p in "${PRIORITY_MODULES[@]}"; do
  if [[ -x "$TARGET_DIR/$p" ]]; then
    RUN_LIST+=("$TARGET_DIR/$p")
  else
    echo "Warning: module not found: $TARGET_DIR/$p" >&2
  fi
done
while IFS= read -r script; do
  RUN_LIST+=("$script")
done < <(
  find "$TARGET_DIR" -maxdepth 1 -type f -name "*.sh" -executable \
    | grep -v -E "/(install-gnome-config|install-nerdfonts|install-gnome-terminal-theme)\.sh$" \
    | sort
)

progress_init "${#RUN_LIST[@]}"
for script in "${RUN_LIST[@]}"; do
  progress_run "Installing $(basename "$script" .sh | sed 's/^install-//')" "$script" all
done
progress_finish

# === Optional Extras ===
EXTRAS_SCRIPT="$SCRIPT_DIR/setup-extras.sh"
if [[ -x "$EXTRAS_SCRIPT" ]]; then
  glimt_section "Optional extras"
  if $VERBOSE; then
    bash "$EXTRAS_SCRIPT" --verbose
  else
    bash "$EXTRAS_SCRIPT"
  fi
else
  echo "Warning: extras script not found: $EXTRAS_SCRIPT" >&2
fi

# === Copy glimt.sh to ~/.local/bin ===
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/glimt.sh" "$HOME/.local/bin/glimt"
chmod +x "$HOME/.local/bin/glimt"

# === Copy autocomplete file (guarded) ===
mkdir -p "$HOME/.zsh/completions"
COMPLETION_FILE="$MODULES_DIR/config/_glimt"
if [[ -f "$COMPLETION_FILE" ]]; then
  # Always overwrite the installed completion so updates take effect immediately.
  cp -f "$COMPLETION_FILE" "$HOME/.zsh/completions/_glimt"
else
  echo "Warning: zsh completion not found: $COMPLETION_FILE" >&2
fi

# Revert to normal idle and lock settings (guard for non-GNOME)
if command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.screensaver lock-enabled true || true
  gsettings set org.gnome.desktop.session idle-delay 300 || true
fi

# === Done ===
echo ""
OS_NAME="Fedora ${VERSION_ID:-}"

gum style --bold "Setup complete"
gum style --faint "$OS_NAME is ready. Reboot to apply all changes."
