### ── fzf-tab + preview (Catppuccin Mocha, minimal) ────────────────────────────

# --- Load fzf-tab (if installed) ---
if [[ -f ~/.zsh/plugins/fzf-tab/fzf-tab.zsh ]]; then
  source ~/.zsh/plugins/fzf-tab/fzf-tab.zsh
  zle -N fzf-tab-complete
  bindkey '^I' fzf-tab-complete
fi

# --- Catppuccin Mocha palette for fzf ---
FZF_CATPPUCCIN_MOCHA="\
--color=fg:#cdd6f4,bg:#1e1e2e,hl:#f38ba8 \
--color=fg+:#cdd6f4,bg+:#313244,hl+:#f38ba8 \
--color=info:#89b4fa,prompt:#f9e2af,pointer:#f5c2e7 \
--color=marker:#94e2d5,spinner:#94e2d5,header:#89b4fa"

# --- Core fzf-tab UI settings ---
zstyle ':fzf-tab:*' show-preview always
zstyle ':fzf-tab:*' fzf-preview-window 'right:60%:0:wrap'   # full-height preview
zstyle ':fzf-tab:*' single-group on
zstyle -e ':fzf-tab:*' fzf-flags 'reply=(${(z)FZF_CATPPUCCIN_MOCHA})'

# --- Preview function: encoding check, autodetect syntax ---
TEXT_PREVIEW='
if [[ -f "$realpath" ]]; then
  size=$( (stat -c%s -- "$realpath" 2>/dev/null || stat -f%z -- "$realpath" 2>/dev/null) || echo 0 )
  if [[ "${size:-0}" -gt 2000000 ]]; then
    printf "File too large to preview (%.1f MB)\n" "$((size/1024/1024.0))"
    exit 0
  fi

  enc=$(file -b --mime-encoding -- "$realpath" 2>/dev/null || echo binary)
  [[ "$enc" == binary ]] && exit 0

  if command -v bat >/dev/null 2>&1; then
    bat --style=numbers --color=always --paging=never --line-range=:500 -- "$realpath" 2>/dev/null
  else
    head -n 500 -- "$realpath" 2>/dev/null
  fi
fi
'

# Apply preview to any file completion
zstyle ":fzf-tab:complete:*" fzf-preview "$TEXT_PREVIEW"

# --- Optional: nice defaults for plain `fzf` CLI usage ---
if command -v fzf >/dev/null 2>&1; then
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
  else
    export FZF_DEFAULT_COMMAND='find . -type f -not -path "*/\.git/*"'
  fi

  export FZF_DEFAULT_OPTS="--height=80% --layout=reverse --border ${(z)FZF_CATPPUCCIN_MOCHA}"
fi
