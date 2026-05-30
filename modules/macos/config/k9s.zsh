# === K9s Zsh completion ===
if command -v k9s &>/dev/null; then
  source <(k9s completion zsh)
fi
