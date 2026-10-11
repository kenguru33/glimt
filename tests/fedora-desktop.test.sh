# Tests for the Fedora desktop modules (GNOME settings, keyboard, icons,
# flatpak, chrome, btrfs). Sourced by run.sh.

FD=modules/fedora

# fake_gsettings — puts a stateful gsettings stub (and a sudo wrapper that lets
# `sudo -u USER [VAR=val...] gsettings|curl|mv ...` through to the stubs) first
# on PATH. Values live in $SB/.gs/<schema>__<key>; `get` on an unset key
# prints "@as []". Every call is recorded in $CALLS.
fake_gsettings() {
  mkdir -p "$SB/bin" "$SB/.gs"
  cat >"$SB/bin/gsettings" <<'EOF'
#!/usr/bin/env bash
echo "gsettings $*" >>"$CALLS"
f="$GLIMT_TEST_HOME/.gs/${2}__${3}"
case "$1" in
  get) if [[ -f "$f" ]]; then cat "$f"; else echo "@as []"; fi ;;
  set) printf '%s\n' "$4" >"$f" ;;
  reset) rm -f "$f" ;;
esac
EOF
  cat >"$SB/bin/sudo" <<EOF
#!/usr/bin/env bash
if [[ "\${1:-}" == -u ]]; then
  args=("\${@:3}")
  while [[ "\${args[0]:-}" == *=* ]]; do args=("\${args[@]:1}"); done
  case "\${args[0]:-}" in
    gsettings|curl|mv) echo "sudo \$*" >>"\$CALLS"; exec "\${args[@]}" ;;
  esac
fi
exec "$STUBS/sudo" "\$@"
EOF
  chmod +x "$SB/bin/gsettings" "$SB/bin/sudo"
  export PATH="$SB/bin:$PATH"
}

gs_set() { printf '%s\n' "$3" >"$SB/.gs/${1}__${2}"; }
gs_get() { cat "$SB/.gs/${1}__${2}" 2>/dev/null || echo "<unset>"; }

# Run a module end-to-end (dispatcher included) — for modules without an OS guard
run_module() { with_timeout 20 "$BASH" "$ROOT/$1" "$2" </dev/null 2>&1; }

# Module definitions plus overrides (e.g. stubbed guards), run like run_module_fn
run_with_overrides() { # <module> <function> <overrides>
  { load_definitions "$ROOT/$1"; printf '%s\n' "$3"; } >"$SB/fixture.sh"
  run_module_fn_abs fedora "$SB/fixture.sh" "$2"
}

# ---------------------------------------------------------------------
# norwegian-mac-keyboard
# ---------------------------------------------------------------------
KB=$FD/install-norwegian-mac-keyboard.sh
KB_SCHEMA=org.gnome.desktop.input-sources

test_norwegian_keyboard_clean_does_not_apply_fix() {
  fake_gsettings
  gs_set $KB_SCHEMA sources "[('xkb', 'no+mac')]"
  gs_set $KB_SCHEMA xkb-options "['caps:escape']"
  local out
  out="$(run_module "$KB" clean)" || fail "$out"
  assert_eq "$(gs_get $KB_SCHEMA xkb-options)" "['caps:escape']" "xkb-options after clean:"
  assert_not_contains "$(calls)" "gsettings set" "clean must not apply the fix"
}

test_norwegian_keyboard_config_appends_option() {
  fake_gsettings
  gs_set $KB_SCHEMA sources "[('xkb', 'no+mac')]"
  gs_set $KB_SCHEMA xkb-options "['caps:escape']"
  local out
  out="$(run_module "$KB" config)" || fail "$out"
  assert_eq "$(gs_get $KB_SCHEMA xkb-options)" "['caps:escape', 'lv3:lalt_switch']" "existing options must be kept:"
  # re-run is a no-op
  out="$(run_module "$KB" all)" || fail "$out"
  assert_eq "$(gs_get $KB_SCHEMA xkb-options)" "['caps:escape', 'lv3:lalt_switch']" "after re-run:"
  assert_eq "$(grep -c '^gsettings set' "$CALLS")" "1" "gsettings set calls:"
}

test_norwegian_keyboard_config_sets_option_when_empty() {
  fake_gsettings
  gs_set $KB_SCHEMA sources "[('xkb', 'no+mac')]"
  local out
  out="$(run_module "$KB" config)" || fail "$out"
  assert_eq "$(gs_get $KB_SCHEMA xkb-options)" "['lv3:lalt_switch']" "xkb-options:"
}

test_norwegian_keyboard_config_skips_other_layouts() {
  fake_gsettings
  gs_set $KB_SCHEMA sources "[('xkb', 'no')]"
  local out
  out="$(run_module "$KB" config)" || fail "$out"
  assert_contains "$out" "NOT selected"
  assert_not_contains "$(calls)" "gsettings set"
}

test_norwegian_keyboard_clean_removes_only_its_option() {
  fake_gsettings
  gs_set $KB_SCHEMA xkb-options "['caps:escape', 'lv3:lalt_switch', 'compose:ralt']"
  local out
  out="$(run_module "$KB" clean)" || fail "$out"
  assert_eq "$(gs_get $KB_SCHEMA xkb-options)" "['caps:escape', 'compose:ralt']" "xkb-options:"
  gs_set $KB_SCHEMA xkb-options "['lv3:lalt_switch']"
  out="$(run_module "$KB" clean)" || fail "$out"
  assert_eq "$(gs_get $KB_SCHEMA xkb-options)" "[]" "xkb-options:"
}

test_norwegian_keyboard_does_not_shadow_run_as_user() {
  assert_not_contains "$(cat "$ROOT/$KB")" "run_as_user() {" "module"
}

# ---------------------------------------------------------------------
# flatpak
# ---------------------------------------------------------------------
test_flatpak_clean_keeps_flatpak_installed() {
  mkdir -p "$SB/bin"
  printf '#!/usr/bin/env bash\necho "flatpak $*" >>"$CALLS"\n[[ "$1" == remote-list ]] && echo flathub\nexit 0\n' >"$SB/bin/flatpak"
  chmod +x "$SB/bin/flatpak"
  local out
  out="$(PATH="$SB/bin:$PATH" run_module_fn fedora $FD/install-flatpak.sh clean_flatpak 2>&1)" || fail "$out"
  assert_contains "$(calls)" "sudo flatpak remote-delete flathub"
  assert_not_contains "$(calls)" "dnf remove" "flatpak is a system component"
}

test_flatpak_install_does_not_repeat_dnf_install() {
  mkdir -p "$SB/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$SB/bin/flatpak"
  chmod +x "$SB/bin/flatpak"
  local out
  out="$(PATH="$SB/bin:$PATH" run_module_fn fedora $FD/install-flatpak.sh install_flatpak 2>&1)" || fail "$out"
  assert_not_contains "$(calls)" "dnf install" "deps already installs flatpak"
  assert_contains "$(calls)" "sudo flatpak remote-add --if-not-exists flathub"
}

# ---------------------------------------------------------------------
# btrfs-config
# ---------------------------------------------------------------------
BTRFS_OVERRIDES='fedora_guard() { :; }
is_btrfs() { return 0; }
has_config() { return 0; }
ensure_kv() { :; }'

test_btrfs_config_disables_cow_in_users_vm_dirs() {
  mkdir -p "$SB/.local/share/gnome-boxes/images" "$SB/.VirtualBox" "$SB/bin"
  printf '#!/usr/bin/env bash\necho "---------------- $2"\n' >"$SB/bin/lsattr"
  chmod +x "$SB/bin/lsattr"
  local out
  out="$(PATH="$SB/bin:$PATH" RPM_INSTALLED=snapper run_with_overrides $FD/install-btrfs-config.sh config "$BTRFS_OVERRIDES" 2>&1)" || fail "$out"
  assert_contains "$(calls)" "sudo chattr +C $SB/.local/share/gnome-boxes/images"
  assert_contains "$(calls)" "sudo chattr +C $SB/.VirtualBox"
}

test_btrfs_config_clean_asks_before_removing_btrfs_assistant() {
  local out
  out="$(RPM_INSTALLED="btrfs-assistant" run_with_overrides $FD/install-btrfs-config.sh clean "$BTRFS_OVERRIDES" 2>&1)" || fail "$out"
  assert_not_contains "$(calls)" "dnf remove -y btrfs-assistant" "removal defaults to no without a terminal"
  : >"$CALLS"
  out="$(GLIMT_ASSUME_YES=1 RPM_INSTALLED="btrfs-assistant" run_with_overrides $FD/install-btrfs-config.sh clean "$BTRFS_OVERRIDES" 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf remove -y btrfs-assistant" "GLIMT_ASSUME_YES=1"
}

# ---------------------------------------------------------------------
# just-perfection
# ---------------------------------------------------------------------
test_just_perfection_clean_strips_uuid_from_enabled_extensions() {
  fake_gsettings
  gs_set org.gnome.shell enabled-extensions "['a@b', 'just-perfection-desktop@just-perfection', 'c@d']"
  local out
  out="$(run_module_fn fedora $FD/install-just-perfection.sh clean_just_perfection 2>&1)" || fail "$out"
  assert_eq "$(gs_get org.gnome.shell enabled-extensions)" "['a@b', 'c@d']" "enabled-extensions:"
}

test_just_perfection_deps_installs_packages() {
  local out
  out="$(run_module_fn fedora $FD/install-just-perfection.sh install_deps 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf install -y curl jq"
}

# ---------------------------------------------------------------------
# papirus-icon-theme
# ---------------------------------------------------------------------
PAPIRUS=$FD/install-papirus-icon-theme.sh

test_papirus_clean_removes_all_variants_and_resets_theme() {
  fake_gsettings
  local v
  for v in Papirus Papirus-Dark Papirus-Light ePapirus ePapirus-Dark Adwaita-custom; do
    mkdir -p "$SB/.local/share/icons/$v"
  done
  gs_set org.gnome.desktop.interface icon-theme "'Papirus-Dark'"
  local out
  out="$(run_module_fn fedora $PAPIRUS clean 2>&1)" || fail "$out"
  for v in Papirus Papirus-Dark Papirus-Light ePapirus ePapirus-Dark; do
    assert_missing "$SB/.local/share/icons/$v"
  done
  assert_exists "$SB/.local/share/icons/Adwaita-custom"
  assert_contains "$(calls)" "gsettings reset org.gnome.desktop.interface icon-theme"
}

test_papirus_clean_keeps_other_icon_theme() {
  fake_gsettings
  gs_set org.gnome.desktop.interface icon-theme "'Adwaita'"
  local out
  out="$(run_module_fn fedora $PAPIRUS clean 2>&1)" || fail "$out"
  assert_not_contains "$(calls)" "gsettings reset" "a theme the user chose must survive"
}

test_papirus_uses_raw_installer_url_unpinned() {
  local src
  src="$(cat "$ROOT/$PAPIRUS")"
  assert_not_contains "$src" "git.io" "deprecated short URL"
  assert_contains "$src" "raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/install.sh"
  assert_not_contains "$(cat "$ROOT/versions.env")" "PAPIRUS" "versions.env"
}

# ---------------------------------------------------------------------
# chrome
# ---------------------------------------------------------------------
test_chrome_skips_cleanly_on_arm() {
  local out
  out="$(FAKE_UNAME_M=aarch64 run_module_fn fedora $FD/install-chrome.sh install_repo 2>&1)" || fail "must not fail setup on aarch64: $out"
  assert_contains "$out" "only published for x86_64"
  assert_not_contains "$(calls)" "dnf " "no dnf calls on aarch64"
}

test_chrome_clean_removes_desktop_override() {
  mkdir -p "$SB/.local/share/applications"
  touch "$SB/.local/share/applications/google-chrome.desktop" "$SB/.local/share/applications/other.desktop"
  local out
  out="$(run_module_fn fedora $FD/install-chrome.sh clean 2>&1)" || fail "$out"
  assert_missing "$SB/.local/share/applications/google-chrome.desktop"
  assert_exists "$SB/.local/share/applications/other.desktop"
}

# ---------------------------------------------------------------------
# gnome-config
# ---------------------------------------------------------------------
test_gnome_config_clean_resets_settings() {
  fake_gsettings
  mkdir -p "$SB/Pictures" && touch "$SB/Pictures/background.jpg"
  gs_set org.gnome.desktop.background picture-uri "'file://$SB/Pictures/background.jpg'"
  gs_set org.gnome.desktop.background picture-uri-dark "'file:///usr/share/backgrounds/mine.jpg'"
  local out
  out="$(run_module_fn fedora $FD/install-gnome-config.sh clean_config 2>&1)" || fail "$out"
  assert_contains "$(calls)" "gsettings reset org.gnome.desktop.interface color-scheme"
  assert_contains "$(calls)" "gsettings reset org.gnome.desktop.interface gtk-theme"
  assert_contains "$(calls)" "gsettings reset org.gnome.desktop.wm.preferences button-layout"
  grep -qx "gsettings reset org.gnome.desktop.background picture-uri" "$CALLS" || fail "picture-uri must be reset"$'\n'"$(calls)"
  assert_not_contains "$(calls)" "reset org.gnome.desktop.background picture-uri-dark" "user's own wallpaper"
  assert_missing "$SB/Pictures/background.jpg"
}

# ---------------------------------------------------------------------
# gnome-extensions
# ---------------------------------------------------------------------
test_gnome_extensions_loads_without_gnome_shell() {
  command -v gnome-shell >/dev/null && skip "gnome-shell present"
  local out
  out="$(run_module_fn fedora $FD/install-gnome-extensions.sh deps 2>&1)" || fail "module must load without gnome-shell: $out"
  assert_contains "$(calls)" "dnf install -y jq curl"
}

# ---------------------------------------------------------------------
# gravatar
# ---------------------------------------------------------------------
GRAVATAR=$FD/install-gravatar.sh

test_gravatar_skips_without_terminal_or_config() {
  local out
  out="$(run_module_fn fedora $GRAVATAR config_avatar 2>&1)" || fail "must not fail or hang: $out"
  assert_contains "$out" "no terminal"
  assert_missing "$SB/.face"
}

test_gravatar_failed_download_does_not_write_face() {
  fake_gsettings
  printf '#!/usr/bin/env bash\necho "curl $*" >>"$CALLS"\nexit 22\n' >"$SB/bin/curl"
  printf '#!/usr/bin/env bash\necho "0123456789abcdef  -"\n' >"$SB/bin/md5sum"
  chmod +x "$SB/bin/curl" "$SB/bin/md5sum"
  mkdir -p "$SB/.config/glimt"
  echo 'gravatar_email="me@example.com"' >"$SB/.config/glimt/set-user-avatar.config"
  local out
  out="$(run_module_fn fedora $GRAVATAR config_avatar 2>&1)" || fail "$out"
  assert_contains "$(calls)" "curl -fsSL"
  assert_contains "$out" "Could not download"
  assert_missing "$SB/.face"
  assert_missing "$SB/.face.tmp"
}

# ---------------------------------------------------------------------
# headers
# ---------------------------------------------------------------------
test_fedora_desktop_module_headers() {
  local m f bad=""
  for m in btrfs-config chrome flatpak gnome-caffeine gnome-config gnome-extensions \
    gnome-terminal-theme gravatar just-perfection norwegian-mac-keyboard papirus-icon-theme; do
    f="$ROOT/$FD/install-$m.sh"
    [[ "$(head -1 "$f")" == "#!/usr/bin/env bash" ]] || bad+=" $m:shebang"
    grep -qxF "trap 'echo \"❌ [\$MODULE_NAME] Error on line \$LINENO\" >&2' ERR" "$f" || bad+=" $m:trap"
    grep -qx "MODULE_NAME=\"$m\"" "$f" || bad+=" $m:MODULE_NAME"
    grep -qx 'ACTION="${1:-all}"' "$f" || bad+=" $m:ACTION"
  done
  [[ -z "$bad" ]] || fail "nonstandard headers:$bad"
}
