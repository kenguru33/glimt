# === Git completion ===
if whence _git &>/dev/null; then
  :
elif [[ -f "$(brew --prefix 2>/dev/null)/share/zsh/site-functions/_git" ]]; then
  fpath=("$(brew --prefix)/share/zsh/site-functions" $fpath)
  autoload -Uz _git
elif [[ -f "$HOME/.zsh/plugins/git/git-completion.zsh" ]]; then
  source "$HOME/.zsh/plugins/git/git-completion.zsh"
fi

# === Git aliases ===
alias g='git'
alias gs='git status'
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
