# === Catppuccin Mocha Color Theme for eza ===
export EZA_COLORS="\
ur=38;5;245:\
uw=38;5;245:\
ux=38;5;245:\
da=38;5;245:\
di=1;34:\
ln=38;5;117:\
ex=1;92:\
or=1;208:\
mi=1;197:\
pi=38;5;173:\
so=38;5;173:\
bd=1;173:\
cd=1;173:\
su=38;5;204:\
sg=38;5;204:\
tw=38;5;216:\
ow=38;5;216:\
st=38;5;216:\
sn=38;5;216:\
ga=38;5;246:\
"

# === eza Aliases with Icons ===
if command -v eza &>/dev/null; then
  # --hyperlink emits OSC 8 links so filenames are clickable (shift+click in
  # the terminal opens them in their default app). Needs zellij osc8_hyperlinks true.
  alias ls='eza --icons --hyperlink'
  alias ll='eza -al --icons --hyperlink --group-directories-first'
  alias la='eza -a --icons --hyperlink'
  alias l='eza -l --icons --hyperlink'
  alias lt='eza --tree --icons --hyperlink'

  if (( $+functions[_ls] )) && [[ ! $+functions[_eza] ]]; then
    compdef _ls eza
  fi
fi
