# === K9s ===
# k9s on macOS defaults to ~/Library/Application Support/k9s; point it at the
# XDG location where glimt deploys the config and Catppuccin skin.
export K9S_CONFIG_DIR="$HOME/.config/k9s"

if command -v k9s &>/dev/null; then
  source <(k9s completion zsh)
fi
