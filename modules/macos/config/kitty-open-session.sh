#!/usr/bin/env zsh
# Open a saved session from the list via an fzf picker. The session opens in a
# new OS window (kitty cannot load a session into an existing one) and the OS
# window the picker was launched from is then closed — emulating "replace the
# current OS window". Bound to ctrl+shift+o in kitty.conf via
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

DEFAULT_SESSION="$HOME/.config/kitty/default.session"
DEFAULT_LABEL="default (global)"

# (N) is the zsh null-glob qualifier: expand to nothing (not an error) when the
# list is empty.
typeset -a files entries
files=("$SESSIONS_DIR"/*.kitty-session(N))
# The global default session (the startup layout) is selectable too, listed
# first; then the saved sessions by bare name.
[[ -f "$DEFAULT_SESSION" ]] && entries+=("$DEFAULT_LABEL")
entries+=("${files[@]:t}")
if (( ${#entries} == 0 )); then
  notify "$SESSIONS_DIR" "No sessions"
  exit 0
fi

# Floating, centered picker: a rounded box inset from the overlay edges, with a
# distinct panel background, themed to match the Catppuccin Mocha kitty colors.
export FZF_DEFAULT_OPTS="--layout=reverse --info=inline --border=rounded --margin=12%,28% --padding=1 --color=fg:#cdd6f4,bg:#181825,hl:#f38ba8,fg+:#cdd6f4,bg+:#313244,hl+:#f38ba8,info:#cba6f7,prompt:#cba6f7,pointer:#f5e0dc,marker:#b4befe,spinner:#f5e0dc,header:#f38ba8,border:#585b70"

# Capture the tab ids of the OS window we were launched from, BEFORE opening the
# session, so we can close it afterwards (kitty has no way to load a session
# into the current OS window — goto_session always makes a new one). This
# emulates "replace the current OS window".
old_tabs="$(kitty @ ls 2>/dev/null | python3 -c '
import json, sys
for osw in json.load(sys.stdin):
    if osw.get("is_focused"):
        print(" or ".join("id:%d" % t["id"] for t in osw["tabs"]))
        break
' 2>/dev/null || true)"

# Pick from the menu; map the choice back to a session-file path.
sel="$(print -l "${entries[@]}" | fzf --prompt='Open session > ')" || exit 0
[[ -n "$sel" ]] || exit 0

if [[ "$sel" == "$DEFAULT_LABEL" ]]; then
  target="$DEFAULT_SESSION"
else
  target="$SESSIONS_DIR/$sel"
fi

# goto_session loads the session into this running instance as a new OS window
# (or switches to it if already open).
kitty @ action "goto_session '${target}'"

# Replace: close the OS window the picker was launched from (this also closes
# this overlay). One compound match so all its tabs close in a single request.
# WARNING: terminates whatever ran in that window.
[[ -n "$old_tabs" ]] && kitty @ close-tab --match "$old_tabs" --no-response 2>/dev/null || true
