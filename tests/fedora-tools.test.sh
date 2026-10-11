# Tests for the Fedora CLI-tool modules: lazyvim, nvim, kubectl, kubectx, k9s,
# helm, azure-cli, btop, nerdfonts. Sourced by run.sh.

FT_MODULES=(lazyvim nvim kubectl kubectx k9s helm azure-cli btop nerdfonts)

# Stubs for this file: `install` without -o/-g (no such group on the test
# machine), `chown` that only records, and `curl` that prints a version for
# plain fetches and writes $FT_CURL_FILE (or "x") to the -o target.
ft_stubs() {
  local d="$SB/.ft-stubs"
  mkdir -p "$d"
  cat >"$d/install" <<'EOF'
#!/usr/bin/env bash
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in -o|-g) shift 2 ;; *) args+=("$1"); shift ;; esac
done
exec /usr/bin/install "${args[@]}"
EOF
  printf '#!/usr/bin/env bash\necho "chown $*" >>"$CALLS"\n' >"$d/chown"
  cat >"$d/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"$CALLS"
while [[ $# -gt 0 ]]; do
  if [[ "$1" == -o ]]; then
    if [[ -n "${FT_CURL_FILE:-}" ]]; then cp "$FT_CURL_FILE" "$2"; else echo x >"$2"; fi
    exit 0
  fi
  shift
done
echo v1.31.0
EOF
  chmod +x "$d"/*
  export PATH="$d:$PATH"
}

# run_module_fn resolves SCRIPT_DIR to the sandbox; point config/ at the repo
ft_link_templates() { ln -s "$ROOT/modules/fedora/config" "$SB/config"; }

# =====================================================================
# Static
# =====================================================================
test_fedora_tools_standard_header() {
  local m f bad=""
  for m in "${FT_MODULES[@]}"; do
    f="$ROOT/modules/fedora/install-$m.sh"
    [[ "$(head -1 "$f")" == "#!/usr/bin/env bash" ]] || bad+=" $m(shebang)"
    grep -qxF "trap 'echo \"[\$MODULE_NAME] error on line \$LINENO\" >&2' ERR" "$f" || bad+=" $m(trap)"
    grep -qx "MODULE_NAME=\"$m\"" "$f" || bad+=" $m(MODULE_NAME)"
  done
  [[ -z "$bad" ]] || fail "non-standard header:$bad"
}

test_fedora_tools_no_broad_chown_or_leaky_traps() {
  local f="$ROOT/modules/fedora"
  ! grep -n 'chown -R' "$f/install-kubectl.sh" "$f/install-helm.sh" "$f/install-k9s.sh" ||
    fail "chown -R on whole home subtrees"
  ! grep -n 'trap .*RETURN' "$f/install-kubectl.sh" || fail "RETURN trap stays set globally"
  ! grep -n '/tmp/' "$f/install-nerdfonts.sh" || fail "fixed /tmp paths in nerdfonts"
  ! grep -nE '>>.*zshrc' "$f/install-k9s.sh" || fail "k9s must not append to ~/.zshrc"
  ! grep -n 'ls -d' "$f/install-lazyvim.sh" || fail "lazyvim restore should use a glob, not ls"
  grep -q '^  install) install_helm ;;' "$f/install-helm.sh" || fail "helm install must not run deps"
}

# =====================================================================
# kubectl / helm: downloads go through verify_binary, temp files cleaned
# =====================================================================
test_kubectl_install_verifies_binary_and_cleans_tmp() {
  ft_stubs
  local out tmp
  out="$(FAKE_UNAME_M=x86_64 run_module_fn fedora modules/fedora/install-kubectl.sh do_install 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dl.k8s.io/release/v1.31.0/bin/linux/amd64/kubectl"
  assert_contains "$(calls)" "sudo install -o $USER -g $USER -m 0755"
  assert_contains "$out" "$SB/.local/bin/kubectl not found" "verify_binary should check kubectl"
  assert_contains "$(calls)" "run_as_user sh -c" "completion must be written as the user"
  assert_not_contains "$(calls)" "chown" "no chown needed"
  # (macOS mktemp ignores TMPDIR, so find the temp file via the curl call)
  tmp="$(sed -n 's/^curl .* -o \([^ ]*\) .*kubectl$/\1/p' "$CALLS")"
  [[ -n "$tmp" ]] || fail "no download call: $(calls)"
  assert_missing "$tmp"
}

test_helm_install_extracts_as_caller_and_verifies() {
  ft_stubs
  mkdir -p "$SB/fixture/linux-amd64"
  printf '#!/bin/sh\necho v3\n' >"$SB/fixture/linux-amd64/helm"
  tar -czf "$SB/helm.tar.gz" -C "$SB/fixture" linux-amd64
  local out tmp
  out="$(HELM_VERSION=vtest FT_CURL_FILE="$SB/helm.tar.gz" FAKE_UNAME_M=x86_64 \
    run_module_fn fedora modules/fedora/install-helm.sh install_helm 2>&1)" || fail "$out"
  tmp="$(sed -n 's/^curl .* -o \(.*\)\/helm\.tar\.gz$/\1/p' "$CALLS")"
  [[ -n "$tmp" ]] || fail "no download call: $(calls)"
  assert_contains "$(calls)" "sudo install -o $USER -g $USER -m 0755 $tmp/linux-amd64/helm $SB/.local/bin/helm"
  assert_not_contains "$(calls)" "run_as_user tar" "extraction must not switch user"
  assert_not_contains "$(calls)" "dnf" "install must not run deps"
  assert_contains "$out" "$SB/.local/bin/helm not found" "verify_binary should check helm"
  assert_missing "$tmp"
}

# =====================================================================
# k9s
# =====================================================================
test_k9s_fedora_config_uses_deploy_config_and_leaves_zshrc() {
  ft_stubs
  ft_link_templates
  local dir="$SB/.config/k9s" out
  mkdir -p "$dir" "$SB/.local/bin"
  printf '#!/bin/sh\n' >"$SB/.local/bin/k9s" && chmod +x "$SB/.local/bin/k9s"
  printf 'k9s:\n  refreshRate: 5\n' >"$dir/config.yaml"
  echo "# my zshrc" >"$SB/.zshrc"
  out="$(run_module_fn fedora modules/fedora/install-k9s.sh config_k9s 2>&1)" || fail "$out"
  cmp -s "$ROOT/modules/fedora/config/k9s-config.yaml" "$dir/config.yaml" || fail "config.yaml differs from template"
  local backups=("$dir"/config.yaml.bak.*)
  [[ -f "${backups[0]}" ]] || fail "user's config.yaml should have been backed up: $out"
  assert_contains "$(cat "${backups[0]}")" "refreshRate: 5" "backup"
  assert_eq "$(cat "$SB/.zshrc")" "# my zshrc" ".zshrc must not be touched:"
  assert_contains "$(calls)" "run_as_user sh -c" "completions must be written as the user"
  assert_exists "$SB/.zsh/config/k9s.zsh"
}

test_k9s_fedora_clean_keeps_unrelated_files() {
  ft_link_templates
  local dir="$SB/.config/k9s" out
  mkdir -p "$dir/skins" "$SB/.zsh/config" "$SB/.local/bin"
  cp "$ROOT/modules/fedora/config/k9s-config.yaml" "$dir/config.yaml"
  touch "$dir/skins/catppuccin-mocha.yaml" "$dir/skins/my-skin.yaml" "$dir/plugins.yaml" \
    "$SB/.zsh/config/k9s.zsh" "$SB/.local/bin/k9s"
  printf '# === ENVIRONMENT ===\nexport PATH="$HOME/.local/bin:$PATH"\nalias x=y\n' >"$SB/.zshrc"
  out="$(run_module_fn fedora modules/fedora/install-k9s.sh clean_k9s 2>&1)" || fail "$out"
  assert_missing "$SB/.local/bin/k9s"
  assert_missing "$SB/.zsh/config/k9s.zsh"
  assert_missing "$dir/config.yaml"
  assert_missing "$dir/skins/catppuccin-mocha.yaml"
  assert_exists "$dir/skins/my-skin.yaml"
  assert_exists "$dir/plugins.yaml"
  assert_not_contains "$(calls)" "sed" "template PATH line (not last) must stay"
}

test_k9s_fedora_clean_keeps_edited_config() {
  ft_link_templates
  local dir="$SB/.config/k9s" out
  mkdir -p "$dir"
  printf 'k9s:\n  refreshRate: 5\n' >"$dir/config.yaml"
  out="$(run_module_fn fedora modules/fedora/install-k9s.sh clean_k9s 2>&1)" || fail "$out"
  assert_exists "$dir/config.yaml"
  assert_contains "$out" "Keeping"
}

test_k9s_fedora_clean_removes_legacy_appended_path_line() {
  ft_link_templates
  printf 'alias x=y\nexport PATH="$HOME/.local/bin:$PATH"\n' >"$SB/.zshrc"
  local out
  out="$(run_module_fn fedora modules/fedora/install-k9s.sh clean_k9s 2>&1)" || fail "$out"
  assert_contains "$(calls)" "run_as_user sed -i \$d $SB/.zshrc"
}

# =====================================================================
# lazyvim
# =====================================================================
test_lazyvim_clean_never_removes_neovim() {
  mkdir -p "$SB/.config/nvim"
  local out
  out="$(GLIMT_ASSUME_YES=1 run_module_fn fedora modules/fedora/install-lazyvim.sh clean_lazyvim 2>&1)" || fail "$out"
  assert_missing "$SB/.config/nvim"
  assert_contains "$(calls)" "dnf remove -y ripgrep"
  local removed
  removed="$(grep '^dnf remove' "$CALLS")"
  assert_not_contains "$removed" "neovim" "neovim belongs to install-nvim.sh"
  assert_not_contains "$removed" "fzf" "fzf belongs to install-fzf.sh"
}

test_lazyvim_config_deploys_catppuccin_template() {
  ft_stubs
  ft_link_templates
  local f="$SB/.config/nvim/lua/plugins/catppuccin.lua" out
  mkdir -p "$(dirname "$f")"
  echo "-- mine" >"$f"
  out="$(run_module_fn fedora modules/fedora/install-lazyvim.sh config_lazyvim 2>&1)" || fail "$out"
  cmp -s "$ROOT/modules/fedora/config/lazyvim-catppuccin.lua" "$f" || fail "catppuccin.lua differs from template"
  compgen -G "$f.bak.*" >/dev/null || fail "existing catppuccin.lua should be backed up"
}

test_lazyvim_restore_picks_latest_backup() {
  ft_stubs
  mkdir -p "$SB/.config/nvim.bak-20240101000000" "$SB/.config/nvim.bak-20250101000000"
  local out
  out="$(run_module_fn fedora modules/fedora/install-lazyvim.sh restore_backup 2>&1)" || fail "$out"
  assert_contains "$(calls)" "mv $SB/.config/nvim.bak-20250101000000 $SB/.config/nvim"
  assert_not_contains "$(calls)" "nvim.bak-20240101000000"
  assert_contains "$out" "No backup found for $SB/.cache/nvim"
}

# =====================================================================
# nerdfonts
# =====================================================================
test_nerdfonts_clean_removes_only_its_own_fonts() {
  local fd="$SB/.local/share/fonts" out
  mkdir -p "$fd/NerdFonts/Hack" "$fd/NerdFonts/FiraCode"
  touch "$fd/NerdFonts/Hack/HackNerdFont-Regular.ttf" "$fd/NerdFonts/Hack/README.md" \
    "$fd/NerdFonts/FiraCode/LICENSE" \
    "$fd/HackNerdFontMono-Bold.ttf" "$fd/JetBrainsMonoNLNerdFont-Regular.ttf" \
    "$fd/MyHackFont.ttf" "$fd/FiraCode-Regular.ttf" "$fd/README.md"
  out="$(NERDFONTS_VERSION=vtest run_module_fn fedora modules/fedora/install-nerdfonts.sh clean_fonts 2>&1)" || fail "$out"
  assert_missing "$fd/NerdFonts/Hack"
  assert_missing "$fd/NerdFonts/FiraCode"
  assert_missing "$fd/HackNerdFontMono-Bold.ttf"
  assert_missing "$fd/JetBrainsMonoNLNerdFont-Regular.ttf"
  assert_exists "$fd/MyHackFont.ttf"
  assert_exists "$fd/FiraCode-Regular.ttf"
  assert_exists "$fd/README.md"
}

test_nerdfonts_clean_succeeds_when_nothing_installed() {
  local out
  out="$(NERDFONTS_VERSION=vtest run_module_fn fedora modules/fedora/install-nerdfonts.sh clean_fonts 2>&1)" ||
    fail "clean must succeed with no fonts installed: $out"
}

# =====================================================================
# Pinned binaries: same version -> no download, other version -> install
# =====================================================================
ft_fake_bin() { # <name> <shell body>
  mkdir -p "$SB/.local/bin"
  printf '#!/bin/sh\n%s\n' "$2" >"$SB/.local/bin/$1"
  chmod +x "$SB/.local/bin/$1"
}

test_helm_same_version_skips_download() {
  ft_stubs
  ft_fake_bin helm 'echo v3.15.0'
  local out
  out="$(HELM_VERSION=v3.15.0 FAKE_UNAME_M=x86_64 \
    run_module_fn fedora modules/fedora/install-helm.sh install_helm 2>&1)" || fail "$out"
  assert_contains "$out" "helm v3.15.0 is up to date"
  assert_not_contains "$(calls)" "curl" "no download when current"
  assert_not_contains "$(calls)" "sudo install" "binary must be left alone"
}

test_helm_other_version_downloads() {
  ft_stubs
  ft_fake_bin helm 'echo v3.14.0'
  mkdir -p "$SB/fixture/linux-amd64"
  printf '#!/bin/sh\necho v3.15.0\n' >"$SB/fixture/linux-amd64/helm"
  tar -czf "$SB/helm.tar.gz" -C "$SB/fixture" linux-amd64
  local out
  out="$(HELM_VERSION=v3.15.0 FT_CURL_FILE="$SB/helm.tar.gz" FAKE_UNAME_M=x86_64 \
    run_module_fn fedora modules/fedora/install-helm.sh install_helm 2>&1)" || fail "$out"
  assert_contains "$(calls)" "get.helm.sh/helm-v3.15.0-linux-amd64.tar.gz"
  assert_contains "$out" "replacing v3.14.0"
}

test_k9s_same_version_skips_download() {
  ft_stubs
  ft_fake_bin k9s 'printf "Version              v0.32.4\nCommit               abc\n"'
  local out
  out="$(K9S_VERSION=v0.32.4 FAKE_UNAME_M=x86_64 \
    run_module_fn fedora modules/fedora/install-k9s.sh install_k9s 2>&1)" || fail "$out"
  assert_contains "$out" "k9s v0.32.4 is up to date"
  assert_not_contains "$(calls)" "curl" "no download when current"
}

test_kubectx_same_version_skips_download() {
  ft_stubs
  ft_fake_bin kubectx 'echo 0.9.5'
  ft_fake_bin kubens 'echo 0.9.5'
  local out
  out="$(KUBECTX_VERSION=v0.9.5 FAKE_UNAME_M=x86_64 \
    run_module_fn fedora modules/fedora/install-kubectx.sh install 2>&1)" || fail "$out"
  assert_contains "$out" "kubectx v0.9.5 is up to date"
  assert_not_contains "$(calls)" "curl" "no download when current"
}

test_kubectl_same_version_skips_download() {
  ft_stubs
  ft_fake_bin kubectl 'echo "Client Version: v1.31.0"'
  local out
  out="$(FAKE_UNAME_M=x86_64 run_module_fn fedora modules/fedora/install-kubectl.sh do_install 2>&1)" || fail "$out"
  assert_contains "$out" "kubectl v1.31.0 is up to date"
  assert_contains "$(calls)" "stable.txt" "latest version is resolved"
  assert_not_contains "$(calls)" "bin/linux/amd64/kubectl" "no download when current"
}
