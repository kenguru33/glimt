#!/bin/bash
set -e

trap 'echo "❌ An error occurred. Exiting." >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES="$SCRIPT_DIR/modules"

# === Default SHOW_OUTPUT is quiet ===
SHOW_OUTPUT="${SHOW_OUTPUT:-0}"

# === Parse optional flags ===
for arg in "$@"; do
  case "$arg" in
  --verbose)
    SHOW_OUTPUT=1
    shift
    ;;
  --quiet)
    SHOW_OUTPUT=0
    shift
    ;;
  esac
done

# === Determine action (e.g. all, install, config, clean) ===
ACTION="${1:-all}"

# === Check for required scripts ===
if [[ ! -x "$MODULES/check-sudo.sh" ]]; then
  echo "❌ Missing or non-executable: $MODULES/check-sudo.sh"
  exit 1
fi

"$MODULES/check-sudo.sh"

# === Function to optionally run with spinner or full output ===
run_with_spinner() {
  TITLE="$1"
  CMD="$2"

  if [[ "$SHOW_OUTPUT" == "1" ]]; then
    echo "▶️ $TITLE"
    bash -c "$CMD"
  else
    gum spin --title "$TITLE" -- bash -c "$CMD"
  fi
}

case "$ACTION" in
all)
  run_with_spinner "Installing k8s tools..." "$MODULES/install-k8s-tools.sh all"
  run_with_spinner "Installing ZSH environment..." "$MODULES/debian/install-zsh.sh all"
  run_with_spinner "Installing extra packages..." "$MODULES/install-extra-packages.sh all"
  run_with_spinner "Installing Git configuration..." "$MODULES/install-git-config.sh all"
  run_with_spinner "Installing Nerd Fonts..." "$MODULES/install-nerdfonts.sh all"
  run_with_spinner "Installing Lazyvim..." "$MODULES/install-lazyvim.sh all"
  ;;
install)
  run_with_spinner "Installing k8s tools..." "$MODULES/install-k8s-tools.sh install"
  run_with_spinner "Installing ZSH environment..." "$MODULES/debian/install-zsh.sh install"
  run_with_spinner "Installing extra packages..." "$MODULES/install-extra-packages.sh install"
  run_with_spinner "Installing Git..." "$MODULES/install-git.sh install"
  run_with_spinner "Installing Nerd Fonts..." "$MODULES/install-nerdfonts.sh install"
  run_with_spinner "Installing Lazyvim..." "$MODULES/install-lazyvim.sh install"
  ;;
config)
  run_with_spinner "Installing k8s tools..." "$MODULES/install-k8s-tools.sh config"
  run_with_spinner "Installing ZSH environment..." "$MODULES/debian/install-zsh.sh config"
  run_with_spinner "Configuring extra packages..." "$MODULES/install-extra-packages.sh config"
  run_with_spinner "Configuring Git..." "$MODULES/install-git.sh config"
  run_with_spinner "Configuring Nerd Fonts..." "$MODULES/install-nerdfonts.sh config"
  run_with_spinner "Configuring Lazyvim..." "$MODULES/install-lazyvim.sh config"

  ;;
clean)
  run_with_spinner "Installing k8s tools..." "$MODULES/install-k8s-tools.sh clena"
  run_with_spinner "Installing ZSH environment..." "$MODULES/debian/install-zsh.sh clean"
  run_with_spinner "Cleaning Git config..." "$MODULES/install-git.sh clean"
  run_with_spinner "Cleaning Nerd Fonts..." "$MODULES/install-nerdfonts.sh clean"
  run_with_spinner "Cleaning extra packages..." "$MODULES/install-extra-packages.sh clean"
  run_with_spinner "Cleaning Lazyvim..." "$MODULES/install-lazyvim.sh clean"
  ;;
*)
  echo "Usage: $0 [--verbose|--quiet] [all|install|config|clean]"
  exit 1
  ;;
esac

echo "✅ Terminal environment '$ACTION' completed successfully!"
