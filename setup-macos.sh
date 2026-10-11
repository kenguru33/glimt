#!/usr/bin/env bash
set -Euo pipefail
trap 'echo "Error: setup failed at line $LINENO: $BASH_COMMAND" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules/macos"

# === Argument Parsing ===
# Default: a single progress bar, module output goes to log files.
# -v/--verbose: show every module's full output instead.
VERBOSE=false
for arg in "$@"; do
  case "$arg" in
  -v | --verbose) VERBOSE=true ;;
  -h | --help)
    echo "Usage: $(basename "$0") [-v|--verbose]"
    exit 0
    ;;
  *)
    echo "Unknown option: $arg" >&2
    exit 1
    ;;
  esac
done

# === macOS guard ===
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Error: setup-macos.sh requires macOS" >&2
  exit 1
fi

# === Capture the sudo password once, up front ===
# Asked before anything privileged runs so neither Homebrew's installer nor the
# modules prompt again. The password is cached for sudo (Homebrew reuses it) and
# written to an askpass helper for modules, which run under a spinner without a
# usable terminal. Survives the Bash re-exec below via the exported paths.
trap 'rm -f "${GLIMT_PW_FILE:-}" "${GLIMT_ASKPASS:-}" 2>/dev/null' EXIT

if [[ -z "${GLIMT_ASKPASS:-}" || ! -f "${GLIMT_PW_FILE:-/nonexistent}" ]]; then
  GLIMT_PW_FILE="$(mktemp -t glimt-sudo)"
  GLIMT_ASKPASS="$(mktemp -t glimt-askpass)"
  chmod 600 "$GLIMT_PW_FILE"
  chmod 700 "$GLIMT_ASKPASS"
  printf '#!/bin/sh\ncat %q\n' "$GLIMT_PW_FILE" > "$GLIMT_ASKPASS"

  while true; do
    printf '[glimt] password for %s: ' "$(id -un)" >&2
    IFS= read -rs glimt_pw; echo >&2
    printf '%s\n' "$glimt_pw" > "$GLIMT_PW_FILE"
    unset glimt_pw
    # -S reads the password from stdin and -v caches it (do NOT use -k here, it
    # would validate without caching, so Homebrew's installer would re-prompt).
    if sudo -S -p '' -v < "$GLIMT_PW_FILE" 2>/dev/null; then break; fi
    echo "Sorry, try again." >&2
  done
  export GLIMT_PW_FILE GLIMT_ASKPASS
fi

# Make the password available to terminal-less module sudo calls. The credential
# was cached by the -v above, so Homebrew's own installer below won't re-prompt.
export SUDO_ASKPASS="$GLIMT_ASKPASS"

# === Bootstrap Homebrew before running any modules ===
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Make brew available in the current shell (path varies by architecture)
if [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# === Ensure a modern Bash, then re-exec under it ===
# macOS ships Bash 3.2, but the modules use associative arrays (declare -A)
# and mapfile, which require Bash 4+. Homebrew prepends its bin to PATH via
# shellenv above, so once bash is installed every `bash "$script"` call below
# resolves to it too.
if (( BASH_VERSINFO[0] < 4 )); then
  if ! brew list bash &>/dev/null; then
    echo "Installing Bash 5..."
    brew install bash -q
  fi
  BREW_BASH="$(brew --prefix)/bin/bash"
  if [[ -x "$BREW_BASH" && -z "${GLIMT_BASH_REEXEC:-}" ]]; then
    export GLIMT_BASH_REEXEC=1
    if [[ "$VERBOSE" == true ]]; then
      exec "$BREW_BASH" "$0" --verbose
    else
      exec "$BREW_BASH" "$0"
    fi
  fi
fi

# === Ensure gum is available ===
if ! command -v gum &>/dev/null; then
  echo "Installing gum..."
  brew install gum -q
fi

brew update -q

# === Progress bar + sudo keepalive ===
source "$SCRIPT_DIR/setup-lib.sh"
# The askpass helper covers sudo -A in modules; keep the plain sudo timestamp
# warm too, for anything (e.g. Homebrew casks) that calls sudo directly.
glimt_sudo_keepalive

# === Header ===
glimt_banner "macOS post-install setup"

# === Heads-up: optional macOS permission ===
gum style --faint \
  "Optional: to set kitty's custom icon, allow your terminal under" \
  "System Settings → Privacy & Security → App Management, then reopen it." \
  "Without it the icon step is skipped."

# === Confirm Start ===
echo ""
gum confirm "Start setup?" || {
  echo "Setup cancelled."
  exit 1
}

glimt_banner "macOS post-install setup"

# === Collect interactive answers up front ===
# git-config prompts for name/email; gather it here so every module below can
# run cleanly under the spinner instead of prompting mid-run. The module writes
# its config file, then skips prompting when it runs under the spinner.
GIT_CONFIG_MODULE="$MODULES_DIR/install-git-config.sh"
if [[ -f "$GIT_CONFIG_MODULE" ]]; then
  glimt_section "Git"
  bash "$GIT_CONFIG_MODULE" prompt
fi

# === Priority modules (run first, order matters) ===
PRIORITY_MODULES=(
  install-nerdfonts.sh
  install-zsh.sh
  install-starship.sh
)

# Build the full run list up front so the progress bar knows the total
RUN_LIST=()
for module in "${PRIORITY_MODULES[@]}"; do
  if [[ -f "$MODULES_DIR/$module" ]]; then
    RUN_LIST+=("$MODULES_DIR/$module")
  else
    echo "Warning: module not found: $MODULES_DIR/$module" >&2
  fi
done

# Remaining modules (alphabetical, skip priority + homebrew)
mapfile -t all_scripts < <(find "$MODULES_DIR" -maxdepth 1 -name 'install-*.sh' -print | sort)
for script in "${all_scripts[@]}"; do
  module="$(basename "$script")"

  skip=false
  for p in "install-homebrew.sh" "${PRIORITY_MODULES[@]}"; do
    [[ "$module" == "$p" ]] && skip=true && break
  done
  $skip && continue

  RUN_LIST+=("$script")
done

glimt_section "Core modules"
progress_init "${#RUN_LIST[@]}"
for script in "${RUN_LIST[@]}"; do
  progress_run "Installing $(basename "$script" .sh | sed 's/^install-//')" bash "$script" all
done
progress_finish

# === Optional Extras ===
EXTRAS_SCRIPT="$SCRIPT_DIR/setup-macos-extras.sh"
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

# === Install glimt CLI ===
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/glimt.sh" "$HOME/.local/bin/glimt"
chmod +x "$HOME/.local/bin/glimt"

# === Install zsh completion ===
mkdir -p "$HOME/.zsh/completions"
COMPLETION_FILE="$MODULES_DIR/config/_glimt"
if [[ -f "$COMPLETION_FILE" ]]; then
  cp -f "$COMPLETION_FILE" "$HOME/.zsh/completions/_glimt"
else
  echo "Warning: zsh completion not found: $COMPLETION_FILE" >&2
fi

# === Done ===
echo ""
gum style --bold "Setup complete"
gum style --faint "Restart your terminal to apply all changes. Manage glimt with: glimt"
