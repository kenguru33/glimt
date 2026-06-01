#!/usr/bin/env bash
set -Euo pipefail
trap 'echo "❌ Setup failed at: $BASH_COMMAND (line $LINENO)" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules/macos"

# === Argument Parsing ===
VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
  VERBOSE=true
  shift
fi

# === macOS guard ===
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌ This setup script is for macOS only."
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

  echo "🔐  Some steps require administrator access. Please enter your password."
  while true; do
    printf '🔐 sudo password: ' >&2
    IFS= read -rs glimt_pw; echo >&2
    printf '%s\n' "$glimt_pw" > "$GLIMT_PW_FILE"
    unset glimt_pw
    # -S reads the password from stdin and -v caches it (do NOT use -k here, it
    # would validate without caching, so Homebrew's installer would re-prompt).
    if sudo -S -p '' -v < "$GLIMT_PW_FILE" 2>/dev/null; then break; fi
    echo "❌ Incorrect password — try again." >&2
  done
  export GLIMT_PW_FILE GLIMT_ASKPASS
fi

# Make the password available to terminal-less module sudo calls. The credential
# was cached by the -v above, so Homebrew's own installer below won't re-prompt.
export SUDO_ASKPASS="$GLIMT_ASKPASS"

# === Bootstrap Homebrew before running any modules ===
if ! command -v brew &>/dev/null; then
  echo "🍺 Homebrew not found. Installing..."
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
    echo "🔁 Installing a modern Bash (macOS ships 3.2)..."
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
  echo "📦 Installing gum..."
  brew install gum -q
fi

brew update -q

# === Helper: run a module with (optional) spinner ===
run_with_spinner() {
  local title="$1"
  shift

  if [[ "${GLIMT_DISABLE_SPIN:-0}" != "1" ]] && \
     command -v gum >/dev/null 2>&1 && \
     [[ -t 1 ]] && [[ -t 2 ]] && \
     [[ -n "${TERM:-}" ]] && [[ "${TERM:-}" != "dumb" ]]; then
    if gum spin --spinner dot --title "$title" -- bash -c '"$@" >/dev/null 2>&1' _ "$@"; then
      :
    else
      echo "▶️  $title"
      "$@"
    fi
  else
    echo "▶️  $title"
    "$@"
  fi
}

run_module() {
  local script="$1"
  local name
  name="$(basename "$script")"

  if $VERBOSE; then
    echo "▶️  Running: $name"
    bash "$script" all
    echo "✅ Finished: $name"
  else
    run_with_spinner "Running $name..." bash "$script" all
    gum style --foreground 10 "✔️  $name finished"
  fi
}

# === Splash Screen ===
clear
cat <<"EOF"

      🌟   ✨
   ✨   G L I M T     🌟
       ✨  The Final Shine for Fresh Installs

EOF

# === Heads-up: optional macOS permission ===
echo ""
gum style --border rounded --padding "0 1" --border-foreground 220 \
  "🔐  Optional: App Management permission" \
  "" \
  "To set kitty's custom icon, Glimt edits /Applications/kitty.app, which" \
  "macOS protects. If you want the icon, grant your terminal app" \
  "(Terminal/iTerm/kitty…) permission first:" \
  "" \
  "  System Settings → Privacy & Security → App Management → enable your" \
  "  terminal, then quit and reopen it." \
  "" \
  "It's optional — without it the icon step is skipped and setup continues."

# === Confirm Start ===
echo ""
gum confirm "🚀 Ready to run all Glimt modules?" || {
  echo "❌ Setup cancelled."
  exit 1
}

clear
cat <<"EOF"

      🌟   ✨
   ✨   G L I M T     🌟
       ✨  The Final Shine for Fresh Installs

EOF

# === Collect interactive answers up front ===
# git-config prompts for name/email; gather it here so every module below can
# run cleanly under the spinner instead of prompting mid-run. The module writes
# its config file, then skips prompting when it runs under the spinner.
GIT_CONFIG_MODULE="$MODULES_DIR/install-git-config.sh"
if [[ -f "$GIT_CONFIG_MODULE" ]]; then
  echo ""
  gum style --foreground 220 --bold "📝 Git configuration"
  bash "$GIT_CONFIG_MODULE" prompt
fi

# === Priority modules (run first, order matters) ===
PRIORITY_MODULES=(
  install-nerdfonts.sh
  install-zsh.sh
  install-starship.sh
)

echo ""
gum style --foreground 220 --bold "📦 Running priority modules..."
for module in "${PRIORITY_MODULES[@]}"; do
  script="$MODULES_DIR/$module"
  if [[ -f "$script" ]]; then
    run_module "$script"
  else
    echo "⚠️  Not found: $script"
  fi
done

# === Remaining modules (alphabetical, skip priority + homebrew) ===
echo ""
gum style --foreground 220 --bold "📦 Running remaining modules..."
mapfile -t all_scripts < <(find "$MODULES_DIR" -maxdepth 1 -name 'install-*.sh' -print | sort)

for script in "${all_scripts[@]}"; do
  module="$(basename "$script")"

  skip=false
  for p in "install-homebrew.sh" "${PRIORITY_MODULES[@]}"; do
    [[ "$module" == "$p" ]] && skip=true && break
  done
  $skip && continue

  run_module "$script"
done

# === Optional Extras ===
EXTRAS_SCRIPT="$SCRIPT_DIR/setup-macos-extras.sh"
if [[ -x "$EXTRAS_SCRIPT" ]]; then
  echo ""
  gum style --foreground 220 --bold "🎛 Installing optional extras..."
  if $VERBOSE; then
    bash "$EXTRAS_SCRIPT" --verbose
  else
    bash "$EXTRAS_SCRIPT" --quiet
  fi
else
  echo "⚠️  Extras script not found: $EXTRAS_SCRIPT"
fi

# === Install glimt CLI ===
mkdir -p "$HOME/.local/bin"
cp "$SCRIPT_DIR/glimt.sh" "$HOME/.local/bin/glimt"
chmod +x "$HOME/.local/bin/glimt"
gum style --foreground 10 "✔️  glimt CLI installed → ~/.local/bin/glimt"

# === Install zsh completion ===
mkdir -p "$HOME/.zsh/completions"
COMPLETION_FILE="$MODULES_DIR/config/_glimt"
if [[ -f "$COMPLETION_FILE" ]]; then
  cp -f "$COMPLETION_FILE" "$HOME/.zsh/completions/_glimt"
  gum style --foreground 10 "✔️  zsh completion installed → ~/.zsh/completions/_glimt"
else
  echo "⚠️  Completion file not found: $COMPLETION_FILE"
fi

# === Done ===
echo ""
gum style --padding "1 4" --margin "1" --align center \
  --foreground 10 --bold \
  "🎉 Glimt setup complete!" "" \
  "$(gum style --foreground 15 "Your macOS system is now ready to use.")" "" \
  "$(gum style --foreground 220 '🔁 Restart your terminal to apply all changes.')"
