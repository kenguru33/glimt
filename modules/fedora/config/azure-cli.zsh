# azure-cli.zsh — Glimt module (Zsh)
# We don't touch your compinit flow. We only enable Bash-compat completion for az.

# Only proceed if az exists
command -v az >/dev/null 2>&1 || return 0

# Enable Bash-style completion within Zsh (idempotent)
autoload -U +X bashcompinit 2>/dev/null
bashcompinit 2>/dev/null

# Try common locations for the azure-cli Bash completion file (Debian/Ubuntu)
# NOTE: Different distros may name the file 'az' or 'azure-cli'
for _glimt_az_comp in \
  /etc/bash_completion.d/azure-cli \
  /etc/bash_completion.d/az \
  /usr/share/bash-completion/completions/az \
  /usr/share/bash-completion/completions/azure-cli \
  /opt/az/etc/bash_completion.d/az
do
  if [[ -r "$_glimt_az_comp" ]]; then
    source "$_glimt_az_comp"
    break
  fi
done
unset _glimt_az_comp
