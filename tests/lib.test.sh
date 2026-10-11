# Tests for the shared module libraries (modules/*/lib.sh). Sourced by run.sh.

test_verify_binary_warns_but_never_aborts_module() {
  local os out
  cat >"$SB/m.sh" <<'M'
install() { verify_binary no-such-binary-xyz --version; echo AFTER-VERIFY; }
M
  for os in fedora macos; do
    out="$(run_module_fn_abs "$os" "$SB/m.sh" install 2>&1)" || fail "[$os] verify_binary aborted the module: $out"
    assert_contains "$out" "AFTER-VERIFY" "[$os]"
    assert_contains "$out" "not found in PATH" "[$os] should still warn"
  done
}

test_run_as_user_skips_sudo_when_already_that_user() {
  cat >"$SB/m.sh" <<'M'
go() { __glimt_real_run_as_user touch "$HOME_DIR/made-by-user"; }
M
  local out
  out="$(run_module_fn_abs fedora "$SB/m.sh" go 2>&1)" || fail "$out"
  assert_exists "$SB/made-by-user"
  assert_not_contains "$(calls)" "sudo" "no sudo needed when already the real user"
}
