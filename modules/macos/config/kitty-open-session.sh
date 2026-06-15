#!/usr/bin/env zsh
# Open a saved session from the list via an fzf picker, loading it into the
# running kitty instance. Bound to ctrl+shift+o in kitty.conf via
# `launch --type=overlay`, so it runs in a transient overlay window with a TTY
# for the fzf picker and for `kitty @` (allow_remote_control yes). fzf is a core
# glimt module (install-fzf.sh), so it is always installed.
set -euo pipefail

# kitty launches helpers with a minimal PATH (no Homebrew) and this script does
# not source ~/.zshrc, so add Homebrew's bin to find fzf (same as zshrc).
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

notify() { osascript -e "display notification \"$2\" with title \"kitty\" subtitle \"$1\"" >/dev/null 2>&1 || true; }

SESSIONS_DIR="$HOME/.local/share/kitty/sessions"

if ! command -v fzf >/dev/null; then
  notify "$SESSIONS_DIR" "fzf not found — cannot pick a session"
  exit 1
fi

# (N) is the zsh null-glob qualifier: expand to nothing (not an error) when the
# list is empty.
typeset -a files
files=("$SESSIONS_DIR"/*.kitty-session(N))
if (( ${#files} == 0 )); then
  notify "$SESSIONS_DIR" "No saved sessions"
  exit 0
fi

# Show bare names in the picker; reconstruct the full path for the chosen one.
sel="$(print -l "${files[@]:t}" | fzf --prompt='Open session > ' --height=100%)" || exit 0
[[ -n "$sel" ]] || exit 0

# goto_session loads the session into this running instance (new OS window, or
# switches to it if already open).
kitty @ action "goto_session '${SESSIONS_DIR}/${sel}'"
