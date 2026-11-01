# === Zellij: project-named sessions and tabs ===
# Sessions and tabs are named after the project you are in, so several Claude
# Code sessions are easy to tell apart (and kitty's tab shows the project).
# Set GLIMT_ZELLIJ_AUTOSTART=0 (e.g. in ~/.zshenv) to stop the auto-start.

# Project of a folder (default $PWD): the git repo it is in, else the folder
# itself; home is "home". Walks up looking for .git (no git subprocess, this
# runs on every cd). Sanitized for zellij names: ".glimt" -> "glimt".
_glimt_project_name() {
  local dir=${1:-$PWD} cur=${1:-$PWD} name
  while [[ -n $cur && $cur != / ]]; do
    if [[ -e $cur/.git ]]; then
      [[ $cur != $HOME ]] && dir=$cur
      break
    fi
    cur=${cur:h}
  done
  if [[ $dir == $HOME ]]; then
    name=home
  else
    name=${dir:t}
  fi
  name=${name//[^A-Za-z0-9_-]/-}
  while [[ $name == -* ]]; do name=${name#-}; done
  print -r -- ${name:-home}
}

# Session to start for this project: the project name if free or exited
# (attach resurrects it), else the first free/exited of name-2, name-3, ...
# A live session is never shared, so two terminals don't mirror each other.
_glimt_zellij_session() {
  local base name n=1 sessions line
  base=$(_glimt_project_name)
  sessions=$(zellij list-sessions --no-formatting 2>/dev/null)
  name=$base
  while :; do
    line=${(M)${(f)sessions}:#${name} *}
    [[ -z $line || $line == *EXITED* ]] && break
    (( n++ ))
    name=$base-$n
  done
  print -r -- $name
}

# Inside zellij: rename the tab after the project when it changes (on cd and
# when the shell starts). Runs in the background so the prompt never waits.
if [[ -n $ZELLIJ ]]; then
  typeset -g _glimt_zellij_tab=""
  _glimt_zellij_rename_tab() {
    local name
    name=$(_glimt_project_name)
    [[ $name == $_glimt_zellij_tab ]] && return
    _glimt_zellij_tab=$name
    zellij action rename-tab "$name" &>/dev/null &!
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd _glimt_zellij_rename_tab
  _glimt_zellij_rename_tab
fi

# === Auto-start Zellij if not already inside ===
if [[ -z $ZELLIJ && -z $TMUX && -n $PS1 && -t 1 ]] \
   && [[ -z $SSH_CONNECTION && -z $VSCODE_GIT_IPC_HANDLE ]] \
   && [[ ${GLIMT_ZELLIJ_AUTOSTART:-1} != 0 ]] \
   && (( $+commands[zellij] )); then
  exec zellij attach --create "$(_glimt_zellij_session)"
fi
