# === kitty session launcher ===
# Wrap `kitty` so that launching it with no arguments restores a session:
#   1. a project-local .kitty.session in the current directory, else
#   2. the global ~/.config/kitty/default.session, else
#   3. a plain kitty window.
# Any explicit arguments (kitty @, kitty +kitten, etc.) bypass the wrapper.
if command -v kitty &>/dev/null; then
  kitty() {
    if [[ $# -gt 0 ]]; then
      command kitty "$@"
    elif [[ -f .kitty.session ]]; then
      # Absolute path: kitty resolves a relative --session against its config
      # dir (~/.config/kitty), not the cwd, so a bare ".kitty.session" fails.
      command kitty --session "$PWD/.kitty.session"
    elif [[ -f ~/.config/kitty/default.session ]]; then
      command kitty --session ~/.config/kitty/default.session
    else
      command kitty
    fi
  }
fi
