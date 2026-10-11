# === Git completion ===
# $HOMEBREW_PREFIX is exported by `brew shellenv` in ~/.zshrc; fall back to
# the standard prefixes rather than spawning brew on every shell start.
_glimt_brew_prefix="${HOMEBREW_PREFIX:-}"
if [[ -z "$_glimt_brew_prefix" ]]; then
  if [[ -d /opt/homebrew ]]; then
    _glimt_brew_prefix=/opt/homebrew
  else
    _glimt_brew_prefix=/usr/local
  fi
fi

if whence _git &>/dev/null; then
  :
elif [[ -f "$_glimt_brew_prefix/share/zsh/site-functions/_git" ]]; then
  fpath=("$_glimt_brew_prefix/share/zsh/site-functions" $fpath)
  autoload -Uz _git
elif [[ -f "$HOME/.zsh/plugins/git/git-completion.zsh" ]]; then
  source "$HOME/.zsh/plugins/git/git-completion.zsh"
fi
unset _glimt_brew_prefix

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
