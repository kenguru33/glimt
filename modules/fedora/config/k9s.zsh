# === K9s Zsh Completion ===
if [[ -x "$HOME/.local/bin/k9s" ]]; then
  source <("$HOME/.local/bin/k9s" completion zsh)
fi
