# Tests for macOS modules and the zsh templates shared in spirit between
# Fedora and macOS. Sourced by run.sh.

# --- nerdfonts -------------------------------------------------------

test_nerdfonts_macos_no_success_log_when_install_fails() {
  # brew stub that reports "not installed" and fails every install
  mkdir -p "$SB/bin"
  cat >"$SB/bin/brew" <<'EOF'
#!/usr/bin/env bash
echo "brew $*" >>"$CALLS"
exit 1
EOF
  chmod +x "$SB/bin/brew"
  local out
  out="$(PATH="$SB/bin:$PATH" run_module_fn macos modules/macos/install-nerdfonts.sh install 2>&1)" ||
    fail "a failed cask install must not abort the module: $out"
  assert_contains "$(calls)" "brew install --cask font-hack-nerd-font"
  assert_contains "$out" "font-hack-nerd-font install failed"
  assert_not_contains "$out" "done" "failed install"
}

test_nerdfonts_macos_logs_success_when_install_works() {
  local out
  out="$(run_module_fn macos modules/macos/install-nerdfonts.sh install 2>&1)" || fail "$out"
  assert_contains "$(calls)" "brew install --cask font-hack-nerd-font"
  assert_not_contains "$out" "install failed"
}

# --- k9s -------------------------------------------------------------

# Modules resolve SCRIPT_DIR from their own path; under run_module_fn that is
# the sandbox, so expose the real templates there.
link_macos_templates() { ln -s "$ROOT/modules/macos/config" "$SB/config"; }

# curl stub that writes a fake skin to the -o target
stub_curl_download() {
  mkdir -p "$SB/bin"
  cat >"$SB/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"$CALLS"
while [[ $# -gt 0 ]]; do
  [[ "$1" == -o ]] && { echo "skin" >"$2"; exit 0; }
  shift
done
EOF
  chmod +x "$SB/bin/curl"
}

test_k9s_macos_config_uses_deploy_config_with_backup() {
  link_macos_templates
  stub_curl_download
  local dir="$SB/.config/k9s" out
  mkdir -p "$dir"
  printf 'k9s:\n  refreshRate: 5\n' >"$dir/config.yaml"
  out="$(PATH="$SB/bin:$PATH" run_module_fn macos modules/macos/install-k9s.sh config 2>&1)" || fail "$out"
  assert_eq "$(cat "$dir/config.yaml")" "$(cat "$ROOT/modules/macos/config/k9s-config.yaml")" "config.yaml:"
  local backups=("$dir"/config.yaml.bak.*)
  [[ -f "${backups[0]}" ]] || fail "user's config.yaml should have been backed up: $out"
  assert_contains "$(cat "${backups[0]}")" "refreshRate: 5" "backup"
  assert_exists "$dir/skins/catppuccin-mocha.yaml"
  assert_exists "$SB/.zsh/config/k9s.zsh"
}

test_k9s_macos_clean_keeps_unrelated_files() {
  link_macos_templates
  local dir="$SB/.config/k9s"
  mkdir -p "$dir/skins" "$SB/.zsh/config"
  cp "$ROOT/modules/macos/config/k9s-config.yaml" "$dir/config.yaml"
  touch "$dir/skins/catppuccin-mocha.yaml" "$dir/skins/my-skin.yaml" \
    "$dir/plugins.yaml" "$dir/aliases.yaml" "$SB/.zsh/config/k9s.zsh"
  local out
  out="$(run_module_fn macos modules/macos/install-k9s.sh clean 2>&1)" || fail "$out"
  assert_missing "$dir/config.yaml"
  assert_missing "$dir/skins/catppuccin-mocha.yaml"
  assert_missing "$SB/.zsh/config/k9s.zsh"
  assert_exists "$dir/skins/my-skin.yaml"
  assert_exists "$dir/plugins.yaml"
  assert_exists "$dir/aliases.yaml"
}

test_k9s_macos_clean_keeps_user_edited_config() {
  link_macos_templates
  local dir="$SB/.config/k9s"
  mkdir -p "$dir/skins"
  printf 'k9s:\n  refreshRate: 5\n' >"$dir/config.yaml"
  touch "$dir/skins/catppuccin-mocha.yaml"
  local out
  out="$(run_module_fn macos modules/macos/install-k9s.sh clean 2>&1)" || fail "$out"
  assert_exists "$dir/config.yaml"
  assert_missing "$dir/skins"
}

test_k9s_macos_clean_removes_empty_dirs() {
  link_macos_templates
  local dir="$SB/.config/k9s"
  mkdir -p "$dir/skins"
  cp "$ROOT/modules/macos/config/k9s-config.yaml" "$dir/config.yaml"
  touch "$dir/skins/catppuccin-mocha.yaml"
  local out
  out="$(run_module_fn macos modules/macos/install-k9s.sh clean 2>&1)" || fail "$out"
  assert_missing "$dir"
  out="$(run_module_fn macos modules/macos/install-k9s.sh clean 2>&1)" ||
    fail "clean must succeed when nothing is installed: $out"
}

# --- zsh templates ---------------------------------------------------

test_edited_zsh_templates_parse() {
  command -v zsh >/dev/null || skip "zsh not installed"
  local f
  for f in modules/macos/config/git.zsh modules/fedora/config/git.zsh \
    modules/macos/config/kubectx.zsh modules/fedora/config/kubectx.zsh; do
    zsh -n "$ROOT/$f" 2>&1 || fail "zsh -n $f"
  done
}

aliases_of() { grep -E '^alias ' "$1" | sort; }

test_git_zsh_aliases_match_across_os() {
  local mac fed
  mac="$(aliases_of "$ROOT/modules/macos/config/git.zsh")"
  fed="$(aliases_of "$ROOT/modules/fedora/config/git.zsh")"
  [[ -n "$mac" ]] || fail "macOS git.zsh defines no aliases"
  assert_eq "$fed" "$mac" "Fedora git.zsh aliases:"
}

test_kubectx_zsh_aliases_match_across_os() {
  assert_eq "$(aliases_of "$ROOT/modules/fedora/config/kubectx.zsh")" \
    "$(aliases_of "$ROOT/modules/macos/config/kubectx.zsh")" "Fedora kubectx.zsh aliases:"
  assert_not_contains "$(cat "$ROOT/modules/fedora/config/kubectx.zsh")" "vendor-completions"
}

test_macos_git_zsh_does_not_fork_brew() {
  assert_not_contains "$(cat "$ROOT/modules/macos/config/git.zsh")" 'brew --prefix'
}

test_macos_git_zsh_uses_homebrew_prefix_completion() {
  command -v zsh >/dev/null || skip "zsh not installed"
  local p="$SB/hb"
  mkdir -p "$p/share/zsh/site-functions"
  printf '#compdef git\n' >"$p/share/zsh/site-functions/_git"
  local out
  out="$(HOMEBREW_PREFIX="$p" zsh -f -c "source '$ROOT/modules/macos/config/git.zsh'; print -l \$fpath; whence gl; (( \${+_glimt_brew_prefix} )) && echo LEAKED; true" 2>&1)" ||
    fail "$out"
  assert_contains "$out" "$p/share/zsh/site-functions"
  assert_contains "$out" "git log --oneline"
  assert_not_contains "$out" "LEAKED"
}

# k9s on macOS defaults to ~/Library/Application Support/k9s, which would
# ignore the config and skin glimt deploys to ~/.config/k9s
test_k9s_macos_zsh_points_k9s_at_xdg_config() {
  assert_contains "$(cat "$ROOT/modules/macos/config/k9s.zsh")" \
    'export K9S_CONFIG_DIR="$HOME/.config/k9s"' "k9s.zsh"
}

# `gs` would shadow Ghostscript
test_git_zsh_has_no_gs_alias() {
  local f
  for f in "$ROOT/modules/fedora/config/git.zsh" "$ROOT/modules/macos/config/git.zsh"; do
    if grep -qE "^alias gs=" "$f"; then fail "${f#"$ROOT"/} defines alias gs"; fi
  done
}

# Under the progress bar there is no terminal: with no saved git info the
# macOS module used to `read </dev/tty` — an invisible prompt that hangs
test_git_config_macos_without_saved_info_or_terminal_does_not_prompt() {
  fs_stubs real-git
  cp "$ROOT/modules/macos/install-git-config.sh" "$SB/gc.sh"
  printf '\nt_apply() {\n  load_git_config\n  configure_git\n}\n' >>"$SB/gc.sh"
  git config --global user.name "Existing Name"
  local out
  out="$(run_module_fn_abs macos "$SB/gc.sh" t_apply 2>&1)" || fail "must not fail or hang: $out"
  assert_contains "$out" "not prompting"
  assert_not_contains "$out" "Full name:"
  assert_eq "$(git config --global user.name)" "Existing Name"
  assert_eq "$(git config --global init.defaultBranch)" "main"
}

test_git_config_macos_uses_saved_info() {
  fs_stubs real-git
  cp "$ROOT/modules/macos/install-git-config.sh" "$SB/gc.sh"
  printf '\nt_apply() {\n  load_git_config\n  configure_git\n}\n' >>"$SB/gc.sh"
  mkdir -p "$SB/.config/glimt"
  printf 'name="Saved Name"\nemail="saved@example.com"\neditor="vim"\nbranch="trunk"\nrebase="true"\n' \
    >"$SB/.config/glimt/user-git-info.config"
  local out
  out="$(run_module_fn_abs macos "$SB/gc.sh" t_apply 2>&1)" || fail "$out"
  assert_eq "$(git config --global user.email)" "saved@example.com"
  assert_eq "$(git config --global init.defaultBranch)" "trunk"
}

# glimt update asks the picker which selected extras are really installed
test_macos_extras_installed_query() {
  [[ "$OS" == Darwin ]] || skip "needs macOS"
  local out
  mkdir -p "$SB/.stubs"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SB/.stubs/zellij"
  chmod +x "$SB/.stubs/zellij"
  out="$(PATH="$SB/.stubs:$PATH" with_timeout 20 "$BASH" "$ROOT/setup-macos-extras.sh" installed zellij nosuch dotnet </dev/null 2>&1)" ||
    fail "$out"
  assert_eq "$(echo $out)" "zellij" "installed:"
}

# --- brew_ensure / mas_install: install missing, upgrade outdated, else skip
test_brew_ensure_installs_upgrades_or_skips() {
  local out
  cat >"$SB/m.sh" <<'EOS'
#!/usr/bin/env bash
set -Eeuo pipefail
MODULE_NAME=t
ACTION=none
EOS
  echo "source '$ROOT/modules/macos/lib.sh'" >>"$SB/m.sh"
  printf 't_run() { brew_ensure bat fzf eza; brew_ensure --cask kitty; }\n' >>"$SB/m.sh"
  out="$(BREW_INSTALLED="bat fzf kitty" GLIMT_BREW_OUTDATED="fzf" run_module_fn_abs macos "$SB/m.sh" t_run 2>&1)" || fail "$out"
  assert_contains "$out" "bat is up to date"
  assert_contains "$out" "kitty is up to date"
  assert_contains "$(calls)" "brew upgrade --formula fzf"
  assert_contains "$(calls)" "brew install --formula eza"
  assert_not_contains "$(calls)" "brew install --formula bat"
  assert_not_contains "$(calls)" "brew upgrade --formula bat"
  assert_not_contains "$(calls)" "brew update" "no per-package auto update"
}

test_brew_cask_install_upgrades_outdated_cask() {
  local out
  out="$(BREW_INSTALLED="discord" GLIMT_BREW_OUTDATED="discord" run_module_fn macos modules/macos/extras/install-discord.sh install 2>&1)" || fail "$out"
  assert_contains "$(calls)" "brew upgrade --cask discord"
  out="$(BREW_INSTALLED="discord" GLIMT_BREW_OUTDATED="" run_module_fn macos modules/macos/extras/install-discord.sh install 2>&1)" || fail "$out"
  assert_contains "$out" "discord is up to date"
}

# --- zellij ----------------------------------------------------------

# Like fx_run_fn (fedora-extras.test.sh) for macOS extras: they resolve
# templates as "$SCRIPT_DIR/../config", so load into $SB/extras with $SB/config
# linked to the real macOS templates.
mx_run_fn() { # <module file under modules/macos/extras> <function> [args...]
  local file="$1" fn="$2"
  shift 2
  mkdir -p "$SB/extras"
  [[ -e "$SB/config" ]] || ln -s "$ROOT/modules/macos/config" "$SB/config"
  local loaded="$SB/extras/$(basename "$file")"
  load_definitions "$ROOT/modules/macos/extras/$file" >"$loaded"
  cat >"$SB/.mx-driver.sh" <<DRIVER
set -Eeuo pipefail
trap 'echo "ERR trap: line \$LINENO: \$BASH_COMMAND" >&2' ERR
MODULE_NAME=test
source "$ROOT/modules/macos/lib.sh"
source "$ROOT/tests/trace-run-as-user.bash"
[[ "\$HOME_DIR" == "$SB" ]] || { echo "SAFETY ABORT: HOME_DIR=\$HOME_DIR" >&2; exit 99; }
source "$loaded"
$fn "\$@"
DRIVER
  with_timeout 20 "$BASH" "$SB/.mx-driver.sh" "$@" </dev/null
}

test_zellij_macos_config_deploys_templates_with_backup() {
  mkdir -p "$SB/.config/zellij"
  echo 'theme "my-own"' >"$SB/.config/zellij/config.kdl"
  local out
  out="$(mx_run_fn install-zellij.sh config 2>&1)" || fail "$out"
  cmp -s "$ROOT/modules/macos/config/zellij.kdl" "$SB/.config/zellij/config.kdl" || fail "config.kdl differs from template"
  compgen -G "$SB/.config/zellij/config.kdl.bak.*" >/dev/null || fail "user's config.kdl should be backed up: $out"
  cmp -s "$ROOT/modules/macos/config/zellij.zsh" "$SB/.zsh/config/zellij.zsh" || fail "zellij.zsh differs from template"
}

test_zellij_macos_clean_keeps_user_layouts_and_edited_config() {
  mkdir -p "$SB/.config/zellij/layouts" "$SB/.zsh/config"
  touch "$SB/.config/zellij/layouts/mine.kdl" "$SB/.zsh/config/zellij.zsh"
  echo "edited" >"$SB/.config/zellij/config.kdl"
  local out
  out="$(mx_run_fn install-zellij.sh clean 2>&1)" || fail "$out"
  assert_exists "$SB/.config/zellij/layouts/mine.kdl"
  assert_exists "$SB/.config/zellij/config.kdl"
  assert_missing "$SB/.zsh/config/zellij.zsh"
  # an untouched config is removed, and the then-empty dir with it
  cp "$ROOT/modules/macos/config/zellij.kdl" "$SB/.config/zellij/config.kdl"
  rm -rf "$SB/.config/zellij/layouts"
  out="$(mx_run_fn install-zellij.sh clean 2>&1)" || fail "$out"
  assert_missing "$SB/.config/zellij"
}

# The macOS and Fedora zellij setups must stay identical apart from clipboard.
test_zellij_templates_match_across_os() {
  local strip='/^copy_command |^paste_command /d'
  assert_eq "$(sed -E "$strip" "$ROOT/modules/macos/config/zellij.kdl")" \
    "$(sed -E "$strip" "$ROOT/modules/fedora/config/zellij.kdl")" "zellij.kdl (minus clipboard lines):"
  cmp -s "$ROOT/modules/macos/config/zellij.zsh" "$ROOT/modules/fedora/config/zellij.zsh" ||
    fail "zellij.zsh differs between macOS and Fedora"
  assert_contains "$(cat "$ROOT/modules/macos/config/zellij.kdl")" 'default_mode "locked"'
  assert_not_contains "$(cat "$ROOT/modules/macos/config/zellij.kdl")" 'bind "Alt p"' "zellij.kdl (Claude's Alt+P)"
}

# Session/tab naming in zellij.zsh, with a stub `zellij` whose list-sessions
# prints $FAKE_LS. Sourcing is safe: auto-start needs a terminal and a real
# zellij on PATH.
test_zellij_zsh_names_sessions_after_the_project() {
  command -v zsh >/dev/null || skip "zsh not installed"
  local h="$SB/home"
  mkdir -p "$h/code/.glimt/.git" "$h/code/.glimt/modules/macos" "$h/My Proj.v2"
  local out
  out="$(HOME="$h" zsh -fc '
    zellij() { print -r -- "$FAKE_LS"; }
    source "$1"
    cd ~/code/.glimt/modules/macos; print "subdir=$(_glimt_project_name)"
    cd ~; print "home=$(_glimt_project_name)"
    cd ~/"My Proj.v2"; print "odd=$(_glimt_project_name)"
    cd ~/code/.glimt
    FAKE_LS=""; print "free=$(_glimt_zellij_session)"
    FAKE_LS="glimt [Created 1h ago] (current)"; print "live=$(_glimt_zellij_session)"
    FAKE_LS="glimt [Created 1h ago] (EXITED - attach to resurrect)"; print "exited=$(_glimt_zellij_session)"
    FAKE_LS=$'"'"'glimt [Created 1h ago]\nglimt-2 [Created 1m ago]'"'"'; print "two=$(_glimt_zellij_session)"
    FAKE_LS="glimt-old [Created 1h ago]"; print "prefix=$(_glimt_zellij_session)"
  ' _ "$ROOT/modules/macos/config/zellij.zsh" </dev/null 2>&1)" || fail "$out"
  assert_contains "$out" "subdir=glimt"
  assert_contains "$out" "home=home"
  assert_contains "$out" "odd=My-Proj-v2"
  assert_contains "$out" "free=glimt"
  assert_contains "$out" "live=glimt-2"
  assert_contains "$out" "exited=glimt"$'\n'
  assert_contains "$out" "two=glimt-3"
  assert_eq "${out##*$'\n'}" "prefix=glimt" "last line:"
}
