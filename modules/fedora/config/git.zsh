# === Git completion (Zsh-native) ===
if whence _git &>/dev/null; then
  # already available
  :
elif [[ -f /usr/share/zsh/site-functions/_git ]]; then
  fpath=(/usr/share/zsh/site-functions $fpath)
  autoload -Uz _git
fi

# === Git aliases ===
alias g='git'
alias gl='git log --oneline --graph --decorate'
alias gp='git pull --rebase'
alias gP='git push'
alias gd='git diff'
alias gc='git commit'
alias gca='git commit --amend'
alias gco='git checkout'
alias gb='git branch'
alias gst='git stash'
alias gsp='git stash pop'
