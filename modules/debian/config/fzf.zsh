# === Load fzf-tab ===
[[ -f ~/.zsh/plugins/fzf-tab/fzf-tab.zsh ]] && source ~/.zsh/plugins/fzf-tab/fzf-tab.zsh
zle -N fzf-tab-complete
bindkey '^I' fzf-tab-complete

# === Catppuccin Mocha colors ===
FZF_CATPPUCCIN_MOCHA="\
--color=fg:#cdd6f4,bg:#1e1e2e,hl:#f38ba8 \
--color=fg+:#cdd6f4,bg+:#313244,hl+:#f38ba8 \
--color=info:#89b4fa,prompt:#f9e2af,pointer:#f5c2e7 \
--color=marker:#94e2d5,spinner:#94e2d5,header:#89b4fa"

# === fzf-tab UI settings ===
zstyle ':fzf-tab:*' show-preview always
zstyle ':fzf-tab:*' fzf-preview-window right:60%:wrap
zstyle ':fzf-tab:*' single-group on
zstyle -e ':fzf-tab:*' fzf-flags 'reply=(${(z)FZF_CATPPUCCIN_MOCHA})'

# === Only show preview for text files ===
TEXT_PREVIEW='[[ -f "$realpath" && "$(file --mime-type -b "$realpath")" == text/* ]] && bat --style=numbers --color=always "$realpath" 2>/dev/null'

for cmd in nvim vim less more bat cat glow; do
  compdef _files $cmd
  zstyle ":fzf-tab:complete:$cmd:*" fzf-preview "$TEXT_PREVIEW"
done

# === Optional: use FZF_DEFAULT_COMMAND for fzf CLI ===
if command -v fzf >/dev/null; then
  export FZF_DEFAULT_COMMAND="fd --type f"
  export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border ${(z)FZF_CATPPUCCIN_MOCHA}"
fi
