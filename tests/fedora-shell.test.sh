# Tests for the Fedora shell/dev-tool modules (bat, eza, fzf, gh, git-config,
# pbcopy, starship, volta, zsh). Sourced by run.sh.

FS_MODULES=(bat eza fzf gh git-config pbcopy starship volta zsh)

# Extra per-test stubs, prepended to PATH: curl/git/gum record their calls and
# never touch the network; `install` drops -o/-g (the test user's group may
# not exist on this machine) and runs the real install. Pass "real-git" to keep
# the real git (git-config tests read back ~/.gitconfig).
fs_stubs() {
  local d="$SB/.stubs"
  mkdir -p "$d"
  # (the sudo stub never reads the piped installer, so ignore SIGPIPE)
  printf '#!/usr/bin/env bash\ntrap "" PIPE\necho "curl $*" >>"$CALLS"\necho "echo installer-script" 2>/dev/null\nexit 0\n' >"$d/curl"
  [[ "${1:-}" == real-git ]] ||
    printf '#!/usr/bin/env bash\necho "git-stub $*" >>"$CALLS"\n' >"$d/git"
  printf '#!/usr/bin/env bash\necho "gum $*" >>"$CALLS"\nexit 1\n' >"$d/gum"
  cat >"$d/install" <<'EOF'
#!/usr/bin/env bash
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in -o|-g) shift 2 ;; *) args+=("$1"); shift ;; esac
done
exec /usr/bin/install "${args[@]}"
EOF
  chmod +x "$d"/*
  export PATH="$d:$PATH"
  # run_module_fn loads a copy of the module from $SB, so its SCRIPT_DIR is
  # $SB: make the templates reachable from there
  ln -sfn "$ROOT/modules/fedora/config" "$SB/config"
}

# =====================================================================
# Static: headers
# =====================================================================
test_fedora_shell_modules_use_standard_header() {
  local m f bad=""
  for m in "${FS_MODULES[@]}"; do
    f="$ROOT/modules/fedora/install-$m.sh"
    [[ "$(sed -n 1p "$f")" == '#!/usr/bin/env bash' ]] || bad+=" $m:shebang"
    grep -qxF "trap 'echo \"[\$MODULE_NAME] error on line \$LINENO\" >&2' ERR" "$f" || bad+=" $m:trap"
    grep -qx "MODULE_NAME=\"$m\"" "$f" || bad+=" $m:MODULE_NAME"
    grep -qx 'ACTION="${1:-all}"' "$f" || bad+=" $m:ACTION"
  done
  [[ -z "$bad" ]] || fail "non-standard header:$bad"
}

# =====================================================================
# bat
# =====================================================================
test_bat_config_is_deployed_from_template() {
  local f="$ROOT/modules/fedora/install-bat.sh"
  assert_exists "$ROOT/modules/fedora/config/bat.config"
  assert_contains "$(cat "$ROOT/modules/fedora/config/bat.config")" '--theme="Catppuccin Mocha"'
  assert_contains "$(cat "$f")" 'deploy_config "$BAT_CONFIG_TEMPLATE" "$BAT_CONFIG_FILE"'
  assert_not_contains "$(cat "$f")" 'sh -c "echo'
}

# =====================================================================
# fzf / zsh plugins: git runs as the user, no chown afterwards
# =====================================================================
test_fzf_install_clones_as_user() {
  fs_stubs
  local out
  out="$(run_module_fn fedora modules/fedora/install-fzf.sh install 2>&1)" || fail "$out"
  assert_contains "$(calls)" "run_as_user git clone --depth=1 https://github.com/Aloxaf/fzf-tab.git $SB/.zsh/plugins/fzf-tab"
  assert_not_contains "$(cat "$ROOT/modules/fedora/install-fzf.sh")" "chown"
}

test_fzf_install_pulls_as_user_when_present() {
  fs_stubs
  mkdir -p "$SB/.zsh/plugins/fzf-tab/.git"
  local out
  out="$(run_module_fn fedora modules/fedora/install-fzf.sh install 2>&1)" || fail "$out"
  assert_contains "$(calls)" "run_as_user git -C $SB/.zsh/plugins/fzf-tab pull"
}

test_zsh_install_clones_plugins_as_user() {
  fs_stubs
  local out
  out="$(run_module_fn fedora modules/fedora/install-zsh.sh install 2>&1)" || fail "$out"
  assert_contains "$(calls)" "run_as_user git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git $SB/.zsh/plugins/zsh-autosuggestions"
  assert_contains "$(calls)" "run_as_user git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git"
  assert_not_contains "$(cat "$ROOT/modules/fedora/install-zsh.sh")" "chown"
}

# =====================================================================
# gh: completion redirect happens in the user's shell
# =====================================================================
test_gh_completion_written_by_user_shell() {
  fs_stubs
  local out
  out="$(run_module_fn fedora modules/fedora/install-gh.sh config 2>&1)" || fail "$out"
  assert_contains "$(calls)" "run_as_user sh -c gh completion -s zsh > \"\$1\" _ $SB/.zsh/plugins/gh/_gh"
  assert_exists "$SB/.zsh/config/gh.zsh"
}

# =====================================================================
# git-config
# =====================================================================
test_git_config_has_install_action() {
  local f="$ROOT/modules/fedora/install-git-config.sh"
  grep -qE '^install\)' "$f" || fail "dispatcher has no install) case"
  fs_stubs
  local out
  out="$(run_module_fn fedora modules/fedora/install-git-config.sh install_git_completion_zsh 2>&1)" || fail "$out"
  assert_contains "$(calls)" "run_as_user curl -fsSL https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.zsh -o $SB/.zsh/plugins/git/git-completion.zsh"
  assert_exists "$SB/.zsh/plugins/git"
}

test_git_config_clean_unsets_all_glimt_keys() {
  git config --global user.name "Test User"
  git config --global init.defaultBranch main
  git config --global core.editor nvim
  git config --global pull.rebase true
  git config --global color.ui auto
  git config --global core.autocrlf input
  git config --global core.pager less
  local out cfg
  out="$(run_module_fn fedora modules/fedora/install-git-config.sh clean_git_config 2>&1)" || fail "$out"
  cfg="$(git config --global --list)"
  for k in init.defaultbranch core.editor pull.rebase color.ui core.autocrlf user.name; do
    assert_not_contains "$cfg" "$k=" "gitconfig"
  done
  assert_contains "$cfg" "core.pager=less" "unrelated settings must survive"
}

# Module copy with a helper that runs load + apply in one process
fs_git_fixture() {
  cp "$ROOT/modules/fedora/install-git-config.sh" "$SB/gc.sh"
  printf '\nt_apply() {\n  load_git_config\n  configure_git\n}\n' >>"$SB/gc.sh"
}

test_git_config_uses_saved_info_without_prompting() {
  fs_stubs real-git
  fs_git_fixture
  mkdir -p "$SB/.config/glimt"
  cat >"$SB/.config/glimt/user-git-info.config" <<'EOF'
name="Saved Name"
email="saved@example.com"
editor="vim"
branch="trunk"
rebase="true"
EOF
  local out
  out="$(run_module_fn_abs fedora "$SB/gc.sh" t_apply 2>&1)" || fail "$out"
  assert_not_contains "$(calls)" "gum " "must not prompt when setup.sh saved the info"
  assert_eq "$(git config --global user.name)" "Saved Name"
  assert_eq "$(git config --global user.email)" "saved@example.com"
  assert_eq "$(git config --global init.defaultBranch)" "trunk"
  assert_eq "$(git config --global core.editor)" "vim"
  assert_eq "$(git config --global pull.rebase)" "true"
}

test_git_config_without_saved_info_or_terminal_does_not_prompt() {
  fs_stubs real-git
  fs_git_fixture
  git config --global user.name "Existing Name"
  local out
  out="$(run_module_fn_abs fedora "$SB/gc.sh" t_apply 2>&1)" || fail "must not fail or hang: $out"
  assert_not_contains "$(calls)" "gum " "no terminal: no prompt"
  assert_contains "$out" "not prompting"
  assert_eq "$(git config --global user.name)" "Existing Name"
  assert_eq "$(git config --global init.defaultBranch)" "main"
}

# =====================================================================
# pbcopy
# =====================================================================
test_pbcopy_clean_keeps_wl_clipboard_without_consent() {
  local out
  out="$(RPM_INSTALLED="wl-clipboard xclip" run_module_fn fedora modules/fedora/install-pbcopy.sh clean 2>&1)" || fail "$out"
  assert_not_contains "$(calls)" "dnf remove -y wl-clipboard" "wl-clipboard removal defaults to no"
  : >"$CALLS"
  out="$(GLIMT_ASSUME_YES=1 RPM_INSTALLED="wl-clipboard xclip" run_module_fn fedora modules/fedora/install-pbcopy.sh clean 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf remove -y wl-clipboard" "GLIMT_ASSUME_YES=1"
}

test_pbcopy_wrappers_written_as_user() {
  local out
  out="$(run_module_fn fedora modules/fedora/install-pbcopy.sh config 2>&1)" || fail "$out"
  assert_contains "$(calls)" "run_as_user tee $SB/.local/bin/pbcopy"
  assert_contains "$(calls)" "run_as_user tee $SB/.local/bin/pbpaste"
  assert_contains "$(calls)" "run_as_user chmod +x $SB/.local/bin/pbcopy $SB/.local/bin/pbpaste"
}

test_pbcopy_install_does_not_repeat_deps() {
  local out
  out="$(RPM_INSTALLED="wl-clipboard xclip" run_module_fn fedora modules/fedora/install-pbcopy.sh install 2>&1)" || fail "$out"
  assert_not_contains "$(calls)" "dnf install" "packages already installed by deps"
}

# =====================================================================
# starship / volta: installers run as the user
# =====================================================================
test_starship_installer_runs_as_user() {
  fs_stubs
  local out
  out="$(run_module_fn fedora modules/fedora/install-starship.sh install 2>&1)" || fail "$out"
  assert_contains "$(calls)" "curl -fsSL https://starship.rs/install.sh"
  assert_contains "$(calls)" "run_as_user sh -s -- -y --bin-dir $SB/.local/bin"
  assert_not_contains "$(cat "$ROOT/modules/fedora/install-starship.sh")" "chown"
}

test_volta_installs_as_user_with_volta_home() {
  fs_stubs
  local out
  out="$(run_module_fn fedora modules/fedora/install-volta.sh install 2>&1)" || fail "$out"
  assert_contains "$(calls)" "curl -fsSL https://get.volta.sh"
  assert_not_contains "$(calls)" "run_as_user curl" "curl itself needs no user switch"
  assert_contains "$(calls)" "run_as_user env VOLTA_HOME=$SB/.volta bash -s -- --skip-setup"
  assert_contains "$(calls)" "run_as_user env VOLTA_HOME=$SB/.volta PATH=$SB/.volta/bin:"
  assert_contains "$(calls)" "$SB/.volta/bin/volta install node"
  assert_contains "$out" "volta not found" "verify_binary should check volta"
}

# =====================================================================
# zsh: templates via deploy_config, login shell warning on clean
# =====================================================================
test_zsh_config_deploys_templates_with_backup() {
  fs_stubs
  echo "my old zshrc" >"$SB/.zshrc"
  local out n
  out="$(run_module_fn fedora modules/fedora/install-zsh.sh config 2>&1)" || fail "$out"
  for n in autosuggestions syntax-highlighting greeting; do
    cmp -s "$ROOT/modules/fedora/config/$n.zsh" "$SB/.zsh/config/$n.zsh" || fail "$n.zsh differs from its template"
  done
  cmp -s "$ROOT/modules/fedora/config/zshrc" "$SB/.zshrc" || fail ".zshrc differs from template"
  compgen -G "$SB/.zshrc.bak.*" >/dev/null || fail "old .zshrc should be backed up by deploy_config"
  compgen -G "$SB/.zshrc.backup.*" >/dev/null && fail "hand-rolled .backup files should be gone"
  return 0
}

test_zsh_clean_warns_when_zsh_is_login_shell() {
  local d="$SB/.stubs" out
  mkdir -p "$d"
  printf '#!/usr/bin/env bash\necho "${2:-user}:x:501:20::$GLIMT_TEST_HOME:/usr/bin/zsh"\n' >"$d/getent"
  chmod +x "$d/getent"
  out="$(PATH="$d:$PATH" run_module_fn fedora modules/fedora/install-zsh.sh clean 2>&1)" || fail "$out"
  assert_contains "$out" "zsh is still the login shell"
  assert_not_contains "$(calls)" "chsh" "clean must not change the login shell itself"
  out="$(run_module_fn fedora modules/fedora/install-zsh.sh clean 2>&1)" || fail "$out"
  assert_not_contains "$out" "still the login shell" "bash login shell: no warning"
}

# =====================================================================
# dnf_ensure: install what is missing, upgrade what is there
# =====================================================================
test_dnf_ensure_installs_missing_and_upgrades_present() {
  local out
  out="$(RPM_INSTALLED="bat curl" run_module_fn fedora modules/fedora/install-fzf.sh deps 2>&1)" || fail "$out"
  assert_contains "$(calls)" "sudo dnf install -y fzf fd-find unzip"
  assert_contains "$(calls)" "sudo dnf upgrade -y bat curl" "installed packages must be upgraded"
}

test_dnf_ensure_skips_upgrade_when_nothing_installed() {
  local out
  out="$(RPM_INSTALLED="" run_module_fn fedora modules/fedora/install-fzf.sh deps 2>&1)" || fail "$out"
  assert_contains "$(calls)" "sudo dnf install -y fzf bat fd-find curl unzip"
  assert_not_contains "$(calls)" "dnf upgrade"
}

test_dnf_ensure_only_upgrades_when_all_installed() {
  local out
  out="$(RPM_INSTALLED="fzf bat fd-find curl unzip" run_module_fn fedora modules/fedora/install-fzf.sh deps 2>&1)" || fail "$out"
  assert_contains "$(calls)" "sudo dnf upgrade -y fzf bat fd-find curl unzip"
  assert_not_contains "$(calls)" "dnf install"
}

test_eza_upgrades_when_installed_from_repo() {
  local out
  out="$(RPM_INSTALLED="eza" run_module_fn fedora modules/fedora/install-eza.sh deps 2>&1)" || fail "$out"
  assert_contains "$(calls)" "sudo dnf upgrade -y eza"
  assert_not_contains "$(calls)" "dnf install"
  assert_not_contains "$(calls)" "copr"
}

# =====================================================================
# starship: tracks the latest release, skips when already current
# =====================================================================
fs_release_curl() { # <tag> — curl stub that also answers the GitHub releases API
  local d="$SB/.stubs"
  mkdir -p "$d"
  {
    printf '#!/usr/bin/env bash\ntrap "" PIPE\necho "curl $*" >>"$CALLS"\n'
    printf '[[ "$*" == *api.github.com* ]] && echo %q\n' "  \"tag_name\": \"$1\","
    printf 'exit 0\n'
  } >"$d/curl"
  chmod +x "$d/curl"
}

fs_fake_starship() { # <version line>
  mkdir -p "$SB/.local/bin"
  printf '#!/bin/sh\necho "%s"\necho "branch:"\n' "$1" >"$SB/.local/bin/starship"
  chmod +x "$SB/.local/bin/starship"
}

test_starship_same_version_skips_installer() {
  fs_stubs
  fs_release_curl v1.20.1
  fs_fake_starship "starship 1.20.1"
  local out
  out="$(run_module_fn fedora modules/fedora/install-starship.sh install 2>&1)" || fail "$out"
  assert_contains "$out" "starship 1.20.1 is up to date"
  assert_not_contains "$(calls)" "starship.rs/install.sh" "no reinstall when current"
}

test_starship_newer_version_runs_installer() {
  fs_stubs
  fs_release_curl v1.21.0
  fs_fake_starship "starship 1.20.1"
  local out
  out="$(run_module_fn fedora modules/fedora/install-starship.sh install 2>&1)" || fail "$out"
  assert_contains "$out" "Updating starship 1.20.1 to 1.21.0"
  assert_contains "$(calls)" "curl -fsSL https://starship.rs/install.sh"
}
