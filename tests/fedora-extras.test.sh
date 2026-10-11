# Tests for the Fedora extras modules (modules/fedora/extras). Sourced by run.sh.

FX_DIR=modules/fedora/extras

# Extras modules resolve templates as "$(dirname "${BASH_SOURCE[0]}")/../config".
# run_module_fn loads definitions into $SB, which would point that at a
# directory outside the sandbox — so load them into $SB/extras instead, with
# $SB/config linked to the real templates.
fx_run_fn() { # <module file under modules/fedora/extras> <function> [args...]
  local file="$1" fn="$2"
  shift 2
  mkdir -p "$SB/extras"
  [[ -e "$SB/config" ]] || ln -s "$ROOT/modules/fedora/config" "$SB/config"
  local loaded="$SB/extras/$(basename "$file")"
  load_definitions "$ROOT/$FX_DIR/$file" >"$loaded"
  cat >"$SB/.fx-driver.sh" <<EOF
set -Eeuo pipefail
trap 'echo "ERR trap: line \$LINENO: \$BASH_COMMAND" >&2' ERR
MODULE_NAME=test
source "$ROOT/modules/fedora/lib.sh"
source "$ROOT/tests/trace-run-as-user.bash"
[[ "\$HOME_DIR" == "$SB" ]] || { echo "SAFETY ABORT: HOME_DIR=\$HOME_DIR" >&2; exit 99; }
source "$loaded"
$fn "\$@"
EOF
  with_timeout 20 "$BASH" "$SB/.fx-driver.sh" "$@" </dev/null
}

# `install -o USER -g USER` fails on macOS (no per-user group): drop -o/-g
fx_stubs() {
  local d="$SB/.fx-stubs"
  mkdir -p "$d"
  cat >"$d/install" <<'EOF'
#!/usr/bin/env bash
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in -o|-g) shift 2 ;; *) args+=("$1"); shift ;; esac
done
exec /usr/bin/install "${args[@]}"
EOF
  chmod +x "$d/install"
  export PATH="$d:$PATH"
}

# Body of a top-level function, for static checks
fx_fn_body() { # <file> <function>
  awk -v f="$2" '$0 ~ "^"f"\\(\\) *\\{" {p=1; next} p && /^}/ {exit} p' "$1"
}

# =====================================================================
# fedora_guard
# =====================================================================
test_fedora_extras_all_use_fedora_guard() {
  local f n bad=""
  for f in "$ROOT/$FX_DIR"/install-*.sh; do
    n="$(basename "$f")"
    grep -q '^fedora_guard() *{' "$f" || bad+=" $n(no fedora_guard)"
    grep -qx 'fedora_guard' "$f" || bad+=" $n(guard never called)"
    grep -q '"\$ID_LIKE"' "$f" && bad+=" $n(unguarded \$ID_LIKE)"
    # os-release may only be sourced inside fedora_guard, never at top level
    grep -qE '^\. /etc/os-release|^if \[\[ -[rf] /etc/os-release' "$f" && bad+=" $n(top-level os-release)"
    # guard must run before the dispatcher
    awk '/^fedora_guard$/ {g=NR} /^case "\$ACTION" in/ {c=NR} END {exit !(g && c && g < c)}' "$f" ||
      bad+=" $n(guard not before dispatcher)"
  done
  [[ -z "$bad" ]] || fail "extras guard problems:$bad"
}

# Every module's guard, pointed at a fake os-release, under set -u
test_fedora_extras_guard_handles_missing_id_like() {
  local f n out bad=""
  for f in "$ROOT/$FX_DIR"/install-*.sh; do
    n="$(basename "$f")"
    { awk '/^fedora_guard\(\) *\{/ {p=1} p {print} p && /^}/ {exit}' "$f" |
        sed "s#/etc/os-release#$SB/os-release#g"
      echo 'check() { fedora_guard; echo GUARD-OK; }'; } >"$SB/guard.sh"

    printf 'ID=fedora\nVERSION_ID=42\n' >"$SB/os-release"    # no ID_LIKE
    out="$(run_module_fn_abs fedora "$SB/guard.sh" check 2>&1)" || bad+=" $n(fedora: $out)"
    [[ "$out" == *GUARD-OK* ]] || bad+=" $n(fedora rejected)"

    printf 'ID=nobara\nID_LIKE="rhel centos fedora"\n' >"$SB/os-release"
    out="$(run_module_fn_abs fedora "$SB/guard.sh" check 2>&1)" || bad+=" $n(ID_LIKE fedora: $out)"

    printf 'ID=arch\n' >"$SB/os-release"
    out="$(run_module_fn_abs fedora "$SB/guard.sh" check 2>&1)" && bad+=" $n(arch accepted)"
    [[ "$out" == *"unbound variable"* ]] && bad+=" $n(arch: $out)"

    rm -f "$SB/os-release"
    out="$(run_module_fn_abs fedora "$SB/guard.sh" check 2>&1)" && bad+=" $n(missing os-release accepted)"
  done
  [[ -z "$bad" ]] || fail "guard failures:$bad"
}

# =====================================================================
# docker-rootless
# =====================================================================
DR=install-docker-rootless.sh

test_docker_rootless_clean_unmasks_and_removes_repo() {
  local out
  out="$(fx_run_fn "$DR" clean 2>&1)" || fail "$out"
  assert_contains "$(calls)" "sudo systemctl unmask docker docker.socket"
  assert_contains "$(calls)" "sudo rm -f /etc/yum.repos.d/docker-ce.repo"
  assert_contains "$(calls)" "dnf remove -y docker-ce docker-ce-cli docker-ce-rootless-extras"
  assert_not_contains "$(calls)" "autoremove" "clean must not autoremove unrelated packages"
}

test_docker_rootless_remove_conflicts_only_installed() {
  local out
  out="$(RPM_INSTALLED="moby-engine" fx_run_fn "$DR" remove_conflicts 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf remove -y moby-engine"
  assert_not_contains "$(calls)" "dnf remove -y docker" "only installed packages are removed"
  : >"$CALLS"
  out="$(RPM_INSTALLED="" fx_run_fn "$DR" remove_conflicts 2>&1)" || fail "$out"
  assert_not_contains "$(calls)" "dnf remove" "nothing installed → nothing removed"
}

test_docker_rootless_all_runs_each_step_once() {
  local f="$ROOT/$FX_DIR/$DR" body
  body="$(fx_fn_body "$f" install)"
  assert_not_contains "$body" "deps" "install() must not re-run deps"
  assert_not_contains "$body" "start_once_then_stop" "install()"
  assert_not_contains "$body" "install_gnome_extension" "install()"
  assert_not_contains "$body" "copy_zsh_config" "install()"
  body="$(fx_fn_body "$f" config)"
  assert_contains "$body" "start_once_then_stop" "config()"
  assert_contains "$body" "install_gnome_extension" "config()"
}

test_docker_rootless_user_systemctl_keeps_session_env() {
  local f="$ROOT/$FX_DIR/$DR"
  assert_not_contains "$(grep -n 'sudo -u "$REAL_USER" systemctl' "$f")" "systemctl" "bare sudo -u systemctl --user"
  assert_contains "$(fx_fn_body "$f" as_user_session)" "DBUS_SESSION_BUS_ADDRESS="
  assert_contains "$(fx_fn_body "$f" as_user_session)" "XDG_RUNTIME_DIR="
}

# =====================================================================
# lens
# =====================================================================
test_lens_clean_removes_only_installed_package() {
  local out
  out="$(RPM_INSTALLED="lens" fx_run_fn install-lens.sh clean_lens 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf remove -y lens"
  assert_not_contains "$(calls)" "dnf remove -y lens-desktop" "lens-desktop is not installed"
  : >"$CALLS"
  out="$(RPM_INSTALLED="lens-desktop" fx_run_fn install-lens.sh clean_lens 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf remove -y lens-desktop"
  assert_not_contains "$(calls)" "dnf remove -y lens"$'\n' "lens is not installed"
}

# =====================================================================
# pika
# =====================================================================
fx_fake_flatpak() { # <remote names...>
  mkdir -p "$SB/bin"
  printf '#!/usr/bin/env bash\n[[ "$1" == remotes ]] && printf "%%s\\n" %s\n' "$*" >"$SB/bin/flatpak"
  chmod +x "$SB/bin/flatpak"
}

test_pika_flathub_detection_is_exact() {
  local out
  fx_fake_flatpak fedora flathub-beta
  out="$(PATH="$SB/bin:$PATH" fx_run_fn install-pika.sh flathub_configured 2>&1)" &&
    fail "flathub-beta must not count as flathub"
  fx_fake_flatpak fedora flathub
  out="$(PATH="$SB/bin:$PATH" fx_run_fn install-pika.sh flathub_configured 2>&1)" ||
    fail "flathub should be detected: $out"
}

test_pika_deps_installs_flatpak() {
  command -v flatpak >/dev/null && skip "flatpak installed on this machine"
  local out
  out="$(fx_run_fn install-pika.sh deps 2>&1)" || fail "deps must install flatpak, not die: $out"
  assert_contains "$(calls)" "dnf install -y flatpak"
}

# =====================================================================
# lazydocker — LAZYDOCKER_VERSION from the environment wins over versions.env
# =====================================================================
test_lazydocker_env_version_override_survives() {
  local r="$SB/repo" out
  mkdir -p "$r/modules/fedora/extras"
  cp "$ROOT/modules/fedora/lib.sh" "$r/modules/fedora/lib.sh"
  echo 'LAZYDOCKER_VERSION="v0.1.0"' >"$r/versions.env"
  # the module header up to (and including) the version handling
  { awk '{print} /^ACTION=/ {exit}' "$ROOT/$FX_DIR/install-lazydocker.sh"
    echo 'echo "VERSION=$LAZYDOCKER_VERSION"'; } >"$r/modules/fedora/extras/install-lazydocker.sh"
  out="$(LAZYDOCKER_VERSION=v9.9.9 with_timeout 20 "$BASH" "$r/modules/fedora/extras/install-lazydocker.sh" 2>&1)" || fail "$out"
  assert_contains "$out" "VERSION=v9.9.9" "env override"
  out="$(unset LAZYDOCKER_VERSION; with_timeout 20 "$BASH" "$r/modules/fedora/extras/install-lazydocker.sh" 2>&1)" || fail "$out"
  assert_contains "$out" "VERSION=v0.1.0" "pinned default from versions.env"
}

# =====================================================================
# notion
# =====================================================================
test_notion_launcher_cleanup_keeps_unrelated_desktop_files() {
  local d="$SB/.local/share/applications" out
  mkdir -p "$d"
  touch "$d/Notion.desktop" "$d/notion-ssb.desktop" "$d/chrome-abcdef-notion.desktop" "$d/my-notion-notes.desktop"
  out="$(fx_run_fn install-notion.sh remove_old_launchers 2>&1)" || fail "$out"
  assert_missing "$d/Notion.desktop"
  assert_exists "$d/notion-ssb.desktop"
  assert_exists "$d/chrome-abcdef-notion.desktop"
  assert_exists "$d/my-notion-notes.desktop"
}

# =====================================================================
# zellij / dotnet — templates via deploy_config
# =====================================================================
test_zellij_config_deploys_kdl_template_with_backup() {
  fx_stubs
  mkdir -p "$SB/.config/zellij"
  echo 'theme "my-own"' >"$SB/.config/zellij/config.kdl"
  local out
  out="$(fx_run_fn install-zellij.sh config 2>&1)" || fail "$out"
  cmp -s "$ROOT/modules/fedora/config/zellij.kdl" "$SB/.config/zellij/config.kdl" || fail "config.kdl differs from template"
  compgen -G "$SB/.config/zellij/config.kdl.bak.*" >/dev/null || fail "user's config.kdl should be backed up: $out"
  cmp -s "$ROOT/modules/fedora/config/zellij.zsh" "$SB/.zsh/config/zellij.zsh" || fail "zellij.zsh differs from template"
}

test_zellij_no_fixed_tmp_paths() {
  assert_not_contains "$(cat "$ROOT/$FX_DIR/install-zellij.sh")" "/tmp/zellij"
  assert_not_contains "$(cat "$ROOT/$FX_DIR/install-zellij.sh")" 'dirname "$0"'
}

test_dotnet_has_full_dispatcher_and_template() {
  local f="$ROOT/$FX_DIR/install-dotnet.sh" a
  for a in deps install config clean all; do
    grep -qE "^ *$a\)" "$f" || fail "dispatcher lacks '$a'"
  done
  assert_not_contains "$(fx_fn_body "$f" install_dotnet)" "ZSH_FILE" "zsh config belongs in config"
  assert_not_contains "$(cat "$f")" '"$DOTNET_BIN" --info' "hard-failing --info"
}

test_dotnet_config_deploys_zsh_template() {
  fx_stubs
  local out
  out="$(fx_run_fn install-dotnet.sh config_dotnet 2>&1)" || fail "$out"
  cmp -s "$ROOT/modules/fedora/config/dotnet.zsh" "$SB/.zsh/config/dotnet.zsh" || fail "dotnet.zsh differs from template"
  assert_contains "$(calls)" "run_as_user tee $SB/.config/environment.d/dotnet.conf" "env file written as the user"
}

test_dotnet_clean_removes_its_files() {
  mkdir -p "$SB/.dotnet/sdk" "$SB/.config/environment.d" "$SB/.zsh/config"
  touch "$SB/.config/environment.d/dotnet.conf" "$SB/.zsh/config/dotnet.zsh" "$SB/.zsh/config/fzf.zsh"
  local out
  out="$(fx_run_fn install-dotnet.sh clean_dotnet 2>&1)" || fail "$out"
  assert_missing "$SB/.dotnet"
  assert_missing "$SB/.config/environment.d/dotnet.conf"
  assert_missing "$SB/.zsh/config/dotnet.zsh"
  assert_exists "$SB/.zsh/config/fzf.zsh"
}

# =====================================================================
# arch-limited modules skip cleanly instead of failing setup
# =====================================================================
test_gitkraken_and_tableplus_skip_on_arm() {
  local out
  out="$(FAKE_UNAME_M=aarch64 fx_run_fn install-gitkraken.sh install_pkg_file 2>&1)" || fail "gitkraken must not fail on aarch64: $out"
  assert_contains "$out" "x86_64 builds only"
  out="$(FAKE_UNAME_M=aarch64 fx_run_fn install-tableplus.sh install_tableplus 2>&1)" || fail "tableplus must not fail on aarch64: $out"
  assert_contains "$out" "x86_64 builds only"
  assert_not_contains "$(calls)" "dnf" "no dnf calls on aarch64"
}

# =====================================================================
# jetbrains-toolbox / claude-code
# =====================================================================
test_jetbrains_toolbox_clean_removes_autostart() {
  mkdir -p "$SB/.config/autostart" "$SB/.local/share/JetBrains/Toolbox" "$SB/.local/bin"
  touch "$SB/.config/autostart/jetbrains-toolbox.desktop" "$SB/.config/autostart/other.desktop"
  local out
  out="$(fx_run_fn install-jetbrains-toolbox.sh clean 2>&1)" || fail "$out"
  assert_missing "$SB/.config/autostart/jetbrains-toolbox.desktop"
  assert_missing "$SB/.local/share/JetBrains/Toolbox"
  assert_exists "$SB/.config/autostart/other.desktop"
}

test_jetbrains_toolbox_deps_installs_tools() {
  local out
  out="$(fx_run_fn install-jetbrains-toolbox.sh deps 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf install -y curl jq tar"
}

test_extras_write_home_files_as_user() {
  # `sudo -u USER cat >file` / `cat >file` redirect in the calling (root) shell
  local hits
  hits="$(grep -nE '(^|[^a-z_])cat >' "$ROOT/$FX_DIR"/install-*.sh || true)"
  [[ -z "$hits" ]] || fail "use run_as_user tee instead of cat >:"$'\n'"$hits"
}

# Docker data (~/.local/share/docker: images, containers, volumes) must never
# be deleted by install/update, and only with explicit consent on clean.
test_docker_rootless_install_keeps_existing_setup_and_data() {
  mkdir -p "$SB/.local/share/docker/volumes/db" "$SB/.config/systemd/user"
  touch "$SB/.config/systemd/user/docker.service"
  local out
  out="$(fx_run_fn "$DR" install 2>&1)" || fail "$out"
  assert_exists "$SB/.local/share/docker/volumes/db"
  assert_exists "$SB/.config/systemd/user/docker.service"
  assert_contains "$out" "already set up"
}

test_docker_rootless_install_sets_up_without_touching_data() {
  mkdir -p "$SB/.local/share/docker/volumes/db" "$SB/.stubs"
  local c
  for c in dockerd-rootless-setuptool.sh systemctl; do
    printf '#!/usr/bin/env bash\necho "%s $*" >>"$CALLS"\n' "$c" >"$SB/.stubs/$c"
    chmod +x "$SB/.stubs/$c"
  done
  local out
  out="$(PATH="$SB/.stubs:$PATH" fx_run_fn "$DR" install 2>&1)" || fail "$out"
  assert_exists "$SB/.local/share/docker/volumes/db"
  assert_contains "$(calls)" "dockerd-rootless-setuptool.sh install" "fresh install must run the setup"
}

test_docker_rootless_clean_keeps_data_unless_confirmed() {
  mkdir -p "$SB/.local/share/docker/volumes/db"
  local out
  out="$(fx_run_fn "$DR" clean 2>&1)" || fail "$out"
  assert_exists "$SB/.local/share/docker/volumes/db"
  out="$(GLIMT_ASSUME_YES=1 fx_run_fn "$DR" clean 2>&1)" || fail "$out"
  assert_missing "$SB/.local/share/docker"
}

test_zellij_clean_keeps_user_layouts_and_edited_config() {
  mkdir -p "$SB/.config/zellij/layouts"
  touch "$SB/.config/zellij/layouts/mine.kdl"
  echo "edited" >"$SB/.config/zellij/config.kdl"
  local out
  out="$(fx_run_fn install-zellij.sh clean 2>&1)" || fail "$out"
  assert_exists "$SB/.config/zellij/layouts/mine.kdl"
  assert_exists "$SB/.config/zellij/config.kdl"
  cp "$ROOT/modules/fedora/config/zellij.kdl" "$SB/.config/zellij/config.kdl"
  rm -rf "$SB/.config/zellij/layouts"
  out="$(fx_run_fn install-zellij.sh clean 2>&1)" || fail "$out"
  assert_missing "$SB/.config/zellij"
}

# =====================================================================
# Flatpak apps: update when installed, install when missing
# =====================================================================
fx_flatpak_with_app() { # <scope where the app is installed: user|system|none>
  mkdir -p "$SB/bin"
  cat >"$SB/bin/flatpak" <<EOF
#!/usr/bin/env bash
echo "flatpak \$*" >>"\$CALLS"
case "\$1" in
  remote-list|remotes) echo flathub ;;
  info) [[ "$1" == any && "\$2" != --* ]] && exit 0
        [[ "\$2" == --$1 ]] && exit 0
        exit 1 ;;
esac
exit 0
EOF
  chmod +x "$SB/bin/flatpak"
}

test_spotify_updates_installed_flatpak_in_its_scope() {
  fx_flatpak_with_app system
  local out
  out="$(PATH="$SB/bin:$PATH" fx_run_fn install-spotify.sh install_spotify 2>&1)" || fail "$out"
  assert_contains "$(calls)" "flatpak update -y --system com.spotify.Client"
  assert_not_contains "$(calls)" "flatpak install"
}

test_spotify_installs_missing_flatpak() {
  fx_flatpak_with_app none
  local out
  out="$(PATH="$SB/bin:$PATH" fx_run_fn install-spotify.sh install_spotify 2>&1)" || fail "$out"
  assert_contains "$(calls)" "flatpak install -y flathub com.spotify.Client"
  assert_not_contains "$(calls)" "flatpak update"
}

test_discord_updates_user_flatpak_as_user() {
  fx_flatpak_with_app user
  local out
  out="$(PATH="$SB/bin:$PATH" fx_run_fn install-discord.sh install_discord 2>&1)" || fail "$out"
  assert_contains "$(calls)" "run_as_user flatpak update -y --user com.discordapp.Discord"
  assert_not_contains "$(calls)" "flatpak install"
}

test_discord_updates_system_flatpak_with_sudo() {
  fx_flatpak_with_app system
  local out
  out="$(PATH="$SB/bin:$PATH" fx_run_fn install-discord.sh install_discord 2>&1)" || fail "$out"
  assert_contains "$(calls)" "sudo flatpak update -y --system com.discordapp.Discord"
  assert_not_contains "$(calls)" "flatpak install"
}

test_pika_updates_installed_flatpak() {
  fx_flatpak_with_app any
  local out
  out="$(PATH="$SB/bin:$PATH" fx_run_fn install-pika.sh install 2>&1)" || fail "$out"
  assert_contains "$(calls)" "flatpak update -y org.gnome.World.PikaBackup"
  assert_not_contains "$(calls)" "flatpak install"
}

# =====================================================================
# lazydocker: pinned version already installed -> no download
# =====================================================================
test_lazydocker_same_version_skips_download() {
  mkdir -p "$SB/.local/bin" "$SB/bin"
  printf '#!/bin/sh\nprintf "Version: 0.23.3\\nDate: x\\n"\n' >"$SB/.local/bin/lazydocker"
  printf '#!/usr/bin/env bash\necho "curl $*" >>"$CALLS"\n' >"$SB/bin/curl"
  chmod +x "$SB/.local/bin/lazydocker" "$SB/bin/curl"
  local out
  out="$(PATH="$SB/bin:$PATH" LAZYDOCKER_VERSION=v0.23.3 fx_run_fn install-lazydocker.sh _download_from_release 2>&1)" || fail "$out"
  assert_contains "$out" "lazydocker v0.23.3 is up to date"
  assert_not_contains "$(calls)" "curl" "no download when current"
}

# =====================================================================
# Repo packages that used to stop at "already installed" now upgrade
# =====================================================================
test_tableplus_and_lens_upgrade_when_installed() {
  local out
  out="$(FAKE_UNAME_M=x86_64 RPM_INSTALLED="tableplus" fx_run_fn install-tableplus.sh install_tableplus 2>&1)" || fail "$out"
  assert_contains "$(calls)" "sudo dnf upgrade -y tableplus"
  assert_not_contains "$(calls)" "addrepo" "repo setup only on first install"
  : >"$CALLS"
  out="$(RPM_INSTALLED="lens" fx_run_fn install-lens.sh install_lens 2>&1)" || fail "$out"
  assert_contains "$(calls)" "sudo dnf upgrade -y lens"
  assert_not_contains "$(calls)" "addrepo" "repo setup only on first install"
}
