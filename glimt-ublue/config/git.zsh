# === Git completion (Zsh-native) ===
if whence _git &>/dev/null; then
  # already available
  :
elif [[ -f /usr/share/zsh/site-functions/_git ]]; then
  fpath=(/usr/share/zsh/site-functions $fpath)
  autoload -Uz _git
fi
