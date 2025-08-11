# === Auto-start Zellij if not already inside ===
if [ -z "$ZELLIJ" ] && [ -z "$TMUX" ] \
   && [ -n "$PS1" ] && [ -t 1 ] \
   && [ -z "$SSH_CONNECTION" ] \
   && [ -z "$VSCODE_GIT_IPC_HANDLE" ];then

  command -v zellij >/dev/null && exec zellij
fi
