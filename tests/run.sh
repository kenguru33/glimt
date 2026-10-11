#!/usr/bin/env bash
# tests/run.sh — Glimt test suite (plain bash, no dependencies).
#
#   bash tests/run.sh            # run everything
#   bash tests/run.sh zsh        # only tests whose name contains "zsh"
#   bash tests/run.sh -v [...]   # also print the output of passing tests
#
# Module code is never run against the real system: sudo/dnf/rpm/brew/getent/
# dscl are replaced by stubs that only record their calls, and every test gets
# a throwaway sandbox as $HOME. Before any module function runs, the driver
# checks that lib.sh resolved HOME_DIR to that sandbox and aborts otherwise.

# Needs Bash 4+ (the Fedora modules use associative arrays). macOS ships 3.2,
# so re-exec under Homebrew's bash when available.
if (( BASH_VERSINFO[0] < 4 )); then
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$b" ]] && exec "$b" "$0" "$@"
  done
  echo "❌ tests need Bash 4+ (brew install bash)" >&2
  exit 1
fi

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERBOSE=false
FILTER=""
for arg in "$@"; do
  case "$arg" in
  -v | --verbose) VERBOSE=true ;;
  *) FILTER="$arg" ;;
  esac
done

T="$(mktemp -d "${TMPDIR:-/tmp}/glimt-tests.XXXXXX")"
trap 'rm -rf "$T"' EXIT
STUBS="$T/stubs"
mkdir -p "$STUBS"
OS="$(uname -s)"

# Bash versions the setup-lib tests run under: setup.sh starts under macOS's
# /bin/bash 3.2, so setup-lib.sh must work there too.
LIB_BASHES=("$BASH")
[[ -x /bin/bash && "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" != "${BASH_VERSINFO[0]}" ]] && LIB_BASHES+=(/bin/bash)

# =====================================================================
# Stubs — record calls to $CALLS, never touch the real system
# =====================================================================
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$STUBS/$1"; chmod +x "$STUBS/$1"; }

# sudo: -n true / -v answer from env; -u USER is dropped; then only commands
# that are themselves stubs (or rm/mkdir confined to the sandbox) are executed.
stub sudo '
echo "sudo $*" >>"$CALLS"
case "${1:-}" in
  -n) shift
      [[ "${1:-}" == true ]] && exit "${SUDO_CACHED_RC:-0}"
      [[ "${1:-}" == -v ]] && exit 0 ;;
  -v) exit "${SUDO_AUTH_RC:-0}" ;;
  -u) shift 2 ;;
esac
[[ $# -gt 0 ]] || exit 0
case "$1" in
  dnf|rpm|brew|git|true) exec "$@" ;;
  rm|rmdir|mkdir|touch)
    for a in "${@:2}"; do
      [[ "$a" == /* && "$a" != "$GLIMT_TEST_HOME"* ]] && exit 0
    done
    exec "$@" ;;
  *) exit 0 ;;
esac'
stub dnf 'echo "dnf $*" >>"$CALLS"'
stub brew '
echo "brew $*" >>"$CALLS"
if [[ "${1:-}" == list ]]; then exit "${BREW_HAS_RC:-1}"; fi'
stub rpm '
echo "rpm $*" >>"$CALLS"
if [[ "${2:-}" == --qf ]]; then echo 7.6.6; exit 0; fi
pkg="${@: -1}"
[[ " ${RPM_INSTALLED:-} " == *" $pkg "* ]]'
stub pwsh 'echo "PowerShell 7.6.6"'
stub getent 'echo "${2:-user}:x:501:20::$GLIMT_TEST_HOME:/bin/bash"'
stub dscl 'echo "NFSHomeDirectory: $GLIMT_TEST_HOME"'
stub uname '
if [[ "${1:-}" == -m && -n "${FAKE_UNAME_M:-}" ]]; then echo "$FAKE_UNAME_M"; exit 0; fi
exec /usr/bin/uname "$@"'

# =====================================================================
# Assertions — on failure, print why and end the test (it runs in a subshell)
# =====================================================================
fail() { echo "ASSERTION FAILED: $*"; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "${3:-} expected [$2], got [$1]"; }
assert_contains() { [[ "$1" == *"$2"* ]] || fail "${3:-output} should contain [$2]"$'\n'"--- actual ---"$'\n'"$1"; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || fail "${3:-output} should not contain [$2]"$'\n'"--- actual ---"$'\n'"$1"; }
assert_exists() { [[ -e "$1" ]] || fail "should exist: ${1#"$SB"/}"; }
assert_missing() { [[ ! -e "$1" ]] || fail "should be removed: ${1#"$SB"/}"; }
calls() { cat "$CALLS" 2>/dev/null || true; }
skip() { echo "SKIP: $*"; exit 200; }

# Run a command with a timeout (no coreutils `timeout` on macOS)
with_timeout() { perl -e 'alarm shift; exec @ARGV or die "exec: $!"' "$@"; }

# =====================================================================
# Module loader
# Keeps only a module's variable assignments, arrays and function
# definitions — drops OS guards, `source "$GLIMT_LIB"` and the case
# dispatcher — so single functions can be called in isolation.
# =====================================================================
load_definitions() {
  awk '
    # inside a heredoc: copy verbatim until its terminator
    hd != "" { print; t = $0; sub(/^[\t]+/, "", t); if (t == hd) hd = ""; next }
    in_fn && /<<-?[ ]*["\x27]?[A-Za-z_]+/ {
      print
      hd = $0; sub(/.*<<-?[ ]*["\x27]?/, "", hd); sub(/[^A-Za-z_].*/, "", hd)
      next
    }
    in_fn  { print; if ($0 ~ /^}/) in_fn = 0; next }
    in_arr { print; if ($0 ~ /^\)/) in_arr = 0; next }
    /^[A-Za-z_][A-Za-z0-9_]*\(\) *\{/ { print; if ($0 !~ /}[[:space:]]*$/) in_fn = 1; next }
    /^(declare -A )?[A-Z_][A-Z0-9_]*=\(/ { print; if ($0 !~ /\)[[:space:]]*$/) in_arr = 1; next }
    /^GLIMT_LIB=|^VERSIONS_ENV=/ { next }
    /^[A-Z_][A-Z0-9_]*=/ { print; next }
  ' "$1"
}

# run_module_fn <fedora|macos> <module path relative to repo> <function> [args...]
# Runs one module function under the module's own `set -Eeuo pipefail`, with
# the real lib.sh, stubs on PATH and stdin closed (non-interactive, like a
# module behind the progress bar). Times out after 20s instead of hanging.
run_module_fn() {
  local os="$1" file="$2" fn="$3"
  shift 3
  local loaded="$SB/.loaded-$(basename "$file")"
  load_definitions "$ROOT/$file" >"$loaded"
  cat >"$SB/.driver.sh" <<EOF
set -Eeuo pipefail
trap 'echo "ERR trap: line \$LINENO: \$BASH_COMMAND" >&2' ERR
MODULE_NAME=test
source "$ROOT/modules/$os/lib.sh"
source "$ROOT/tests/trace-run-as-user.bash"
if [[ "\$HOME_DIR" != "$SB" ]]; then
  echo "SAFETY ABORT: HOME_DIR=\$HOME_DIR is not the test sandbox" >&2
  exit 99
fi
source "$loaded"
$fn "\$@"
EOF
  with_timeout 20 "$BASH" "$SB/.driver.sh" "$@" </dev/null
}

# run_lib_script <bash> — run stdin as a script that has setup-lib.sh sourced
run_lib_script() {
  local b="$1" script="$SB/.lib-script.sh"
  { echo "set -Eeuo pipefail"
    echo "trap 'echo ERRTRAP line \$LINENO' ERR"
    echo "source '$ROOT/setup-lib.sh'"
    cat; } >"$script"
  with_timeout 20 "$b" "$script" </dev/null
}

# Run a command inside a pseudo-terminal (BSD vs util-linux `script`), with a
# 30s timeout; the terminal output ends up in $SB/.typescript
in_tty() {
  if [[ "$OS" == Darwin ]]; then
    with_timeout 30 script -q "$SB/.typescript" "$@"
  else
    with_timeout 30 script -qec "$(printf '%q ' "$@")" "$SB/.typescript"
  fi
}

repeat() { local s="" i; for ((i = 0; i < $2; i++)); do s+="$1"; done; printf '%s' "$s"; }

# =====================================================================
# Tests: static checks
# =====================================================================
test_all_scripts_parse() {
  local f bad=""
  while IFS= read -r f; do
    if head -1 "$f" | grep -q zsh || grep -q "zsh .*$(basename "$f")" "$ROOT"/modules/*/config/kitty.conf 2>/dev/null; then
      command -v zsh >/dev/null || continue
      zsh -n "$f" 2>/dev/null || bad+=" ${f#"$ROOT"/}"
    else
      bash -n "$f" 2>/dev/null || bad+=" ${f#"$ROOT"/}"
    fi
  done < <(find "$ROOT" -name '*.sh' -not -path '*/.git/*')
  [[ -z "$bad" ]] || fail "syntax errors in:$bad"
}

test_modules_are_executable() {
  local f bad=""
  while IFS= read -r f; do
    [[ -x "$f" ]] || bad+=" ${f#"$ROOT"/}"
  done < <(find "$ROOT/modules" -name 'install-*.sh')
  [[ -z "$bad" ]] || fail "not executable:$bad"
}

# clean runs non-interactively (extras deselection, glimt clean, progress bar),
# so prompts there must go through confirm(), never a bare read.
test_no_bare_read_prompts_in_clean() {
  local f hits=""
  while IFS= read -r f; do
    hits+="$(awk -v f="${f#"$ROOT"/}" '
      /^clean[A-Za-z_]*\(\) *\{/ { p = 1 }
      p && /read -r?p/ { print f ":" NR ": " $0 }
      p && /^}/ { p = 0 }' "$f")"
  done < <(find "$ROOT/modules" -name 'install-*.sh')
  [[ -z "$hits" ]] || fail "clean must use confirm() instead of read:"$'\n'"$hits"
}

# Every module listed in an extras picker must exist, and descriptions must
# cover exactly the same keys.
picker_keys() { # <file> <array name>
  awk -v a="$2" '$0 ~ "^declare -A "a"=\\(" {p=1; next} p && /^\)/ {exit} p' "$1" |
    sed -E 's/^[[:space:]]*\[?"?([^]"=]+)"?\]?=.*/\1/' | sort
}

test_fedora_extras_picker_matches_modules() {
  local f="$ROOT/setup-extras.sh" k missing=""
  assert_eq "$(picker_keys "$f" MODULES)" "$(picker_keys "$f" MODULE_DESCRIPTIONS)" "MODULES vs MODULE_DESCRIPTIONS keys:"
  for k in $(picker_keys "$f" MODULES); do
    [[ -x "$ROOT/modules/fedora/extras/install-$k.sh" ]] || missing+=" $k"
  done
  [[ -z "$missing" ]] || fail "picker lists modules with no installer:$missing"
  assert_contains "$(picker_keys "$f" MODULES)" "powershell" "Fedora picker"
}

test_macos_extras_picker_matches_modules() {
  local f="$ROOT/setup-macos-extras.sh" k missing="" ordered
  ordered="$(awk '/^ORDERED_MODULES=\(/ {p=1; next} p && /^\)/ {exit} p {gsub(/[[:space:]]/, ""); print}' "$f" | sort)"
  assert_eq "$ordered" "$(picker_keys "$f" MODULES)" "ORDERED_MODULES vs MODULES keys:"
  assert_eq "$(picker_keys "$f" MODULES)" "$(picker_keys "$f" MODULE_DESCRIPTIONS)" "MODULES vs MODULE_DESCRIPTIONS keys:"
  for k in $ordered; do
    [[ -x "$ROOT/modules/macos/extras/install-$k.sh" ]] || missing+=" $k"
  done
  [[ -z "$missing" ]] || fail "picker lists modules with no installer:$missing"
  assert_contains "$ordered" "powershell" "macOS picker"
}

# =====================================================================
# Tests: setup-lib.sh — progress bar
# =====================================================================
test_progress_bar_rendering() {
  local b out
  for b in "${LIB_BASHES[@]}"; do
    out="$(run_lib_script "$b" <<'EOF'
_progress_bar 0 20; echo
_progress_bar 7 20; echo
_progress_bar 20 20; echo
_progress_bar 0 0; echo
EOF
)" || fail "[$b] script failed: $out"
    assert_eq "$(sed -n 1p <<<"$out")" "$(repeat ░ 30)   0% (0/20)" "[$b] 0/20:"
    assert_eq "$(sed -n 2p <<<"$out")" "$(repeat █ 10)$(repeat ░ 20)  35% (7/20)" "[$b] 7/20:"
    assert_eq "$(sed -n 3p <<<"$out")" "$(repeat █ 30) 100% (20/20)" "[$b] 20/20:"
    assert_contains "$(sed -n 4p <<<"$out")" "(0/1)" "[$b] total 0 must not divide by zero:"
  done
}

test_progress_run_hides_output_and_survives_failures() {
  local b out
  for b in "${LIB_BASHES[@]}"; do
    rm -rf "$SB/logs"
    out="$(GLIMT_LOG_DIR="$SB/logs" run_lib_script "$b" 2>&1 <<'EOF'
progress_init 3
progress_run "install-ok.sh" bash -c 'echo hidden-module-output'
progress_run "install-bad.sh" bash -c 'echo boom-line; exit 3'
progress_run "install-ok2.sh" true
echo "failed=[${PROGRESS_FAILED[*]}] done=$PROGRESS_DONE"
progress_finish
echo END
EOF
)" || fail "[$b] a failing module must not abort the orchestrator: $out"
    assert_contains "$out" "END" "[$b]"
    assert_not_contains "$out" "ERRTRAP" "[$b] ERR trap must not fire"
    assert_contains "$out" "failed=[install-bad.sh] done=3" "[$b]"
    assert_not_contains "$out" "hidden-module-output" "[$b] module output must go to the log"
    assert_contains "$out" "install-bad.sh failed (exit 3)" "[$b]"
    assert_contains "$out" "boom-line" "[$b] failure must show the log tail"
    assert_contains "$out" "Failed: install-bad.sh" "[$b]"
    assert_contains "$out" "100% (3/3)" "[$b]"
    assert_contains "$(cat "$SB/logs/install-ok.sh.log")" "hidden-module-output" "[$b] log file"
  done
}

test_progress_finish_no_summary_when_all_ok() {
  local out
  out="$(GLIMT_LOG_DIR="$SB/logs" run_lib_script "$BASH" 2>&1 <<'EOF'
progress_init 2
progress_run a true
progress_run b true
progress_finish
EOF
)" || fail "$out"
  assert_contains "$out" "100% (2/2)"
  assert_not_contains "$out" "failed"
}

test_progress_run_verbose_shows_output() {
  local b out
  for b in "${LIB_BASHES[@]}"; do
    out="$(GLIMT_LOG_DIR="$SB/logs" VERBOSE=true run_lib_script "$b" 2>&1 <<'EOF'
VERBOSE=true
progress_init 2
progress_run "install-ok.sh" bash -c 'echo visible-module-output'
progress_run "install-bad.sh" bash -c 'exit 4'
progress_finish
echo END
EOF
)" || fail "[$b] $out"
    assert_contains "$out" "visible-module-output" "[$b] verbose must show module output"
    assert_contains "$out" "==> install-ok.sh" "[$b]"
    assert_contains "$out" "✗ install-bad.sh failed (exit 4)" "[$b]"
    assert_not_contains "$out" "░" "[$b] verbose must not draw a bar"
    assert_contains "$out" "END" "[$b]"
  done
}

test_progress_log_names_are_sanitized() {
  run_lib_script "$BASH" >/dev/null 2>&1 <<EOF
GLIMT_LOG_DIR="$SB/logs"
progress_init 1
progress_run "Installing foo/bar baz" true
EOF
  assert_exists "$SB/logs/Installing_foo_bar_baz.log"
}

test_progress_tty_with_gum() {
  command -v gum >/dev/null || skip "gum not installed"
  local out
  cat >"$SB/tty.sh" <<EOF
set -Eeuo pipefail
stty cols 120 rows 40 2>/dev/null || true  # the test pty has no size of its own
source '$ROOT/setup-lib.sh'
GLIMT_LOG_DIR='$SB/logs'
progress_init 2
progress_run install-ok.sh bash -c 'sleep 0.3; echo hidden-module-output'
progress_run install-bad.sh bash -c 'echo boom-line; exit 2'
progress_finish
echo END
EOF
  # keep stdin open: an immediate EOF on the pty makes gum skip rendering
  sleep 15 | in_tty env TERM=xterm-256color "$BASH" "$SB/tty.sh" >/dev/null 2>&1
  out="$(cat "$SB/.typescript")"
  assert_contains "$out" "END" "terminal output"
  assert_contains "$out" "(0/2)  install-ok.sh" "spinner title should carry the bar"
  assert_not_contains "$out" "hidden-module-output" "terminal output"
  assert_contains "$out" "boom-line" "terminal output"
  assert_contains "$(cat "$SB/logs/install-ok.sh.log")" "hidden-module-output" "log file"
}

test_progress_tty_without_gum() {
  local out
  cat >"$SB/tty.sh" <<EOF
set -Eeuo pipefail
stty cols 120 rows 40 2>/dev/null || true  # the test pty has no size of its own
source '$ROOT/setup-lib.sh'
GLIMT_LOG_DIR='$SB/logs'
progress_init 1
progress_run install-ok.sh bash -c 'echo hidden-module-output'
progress_finish
echo END
EOF
  # PATH without gum
  sleep 15 | in_tty env TERM=xterm-256color PATH="$STUBS:/usr/bin:/bin" "$BASH" "$SB/tty.sh" >/dev/null 2>&1
  out="$(cat "$SB/.typescript")"
  assert_contains "$out" "(0/1)  install-ok.sh" "plain bar line"
  assert_contains "$out" "100% (1/1)"
  assert_not_contains "$out" "hidden-module-output"
  assert_contains "$out" "END"
}

# =====================================================================
# Tests: setup-lib.sh — sudo up front
# =====================================================================
test_require_sudo_when_cached_does_not_prompt() {
  local b out
  for b in "${LIB_BASHES[@]}"; do
    : >"$CALLS"
    out="$(SUDO_CACHED_RC=0 run_lib_script "$b" 2>&1 <<'EOF'
glimt_require_sudo
pid=$GLIMT_SUDO_KEEPALIVE_PID
kill -0 "$pid" && echo "keepalive-running"
glimt_sudo_keepalive
[[ "$GLIMT_SUDO_KEEPALIVE_PID" == "$pid" ]] && echo "keepalive-reused"
for _ in 1 2 3 4 5 6 7 8 9 10; do grep -q -- '-n -v' "$CALLS" && break; sleep 0.2; done
kill "$pid"
EOF
)" || fail "[$b] $out"
    assert_not_contains "$out" "Enter your password" "[$b]"
    assert_contains "$out" "keepalive-running" "[$b]"
    assert_contains "$out" "keepalive-reused" "[$b] second call must not start another loop"
    assert_not_contains "$(calls)" "sudo -v" "[$b] cached credential: no prompt"
    assert_contains "$(calls)" "sudo -n -v" "[$b] keepalive should refresh the timestamp"
  done
}

test_require_sudo_prompts_once_when_not_cached() {
  local out
  out="$(SUDO_CACHED_RC=1 SUDO_AUTH_RC=0 run_lib_script "$BASH" 2>&1 <<'EOF'
glimt_require_sudo
kill "$GLIMT_SUDO_KEEPALIVE_PID"
echo END
EOF
)" || fail "$out"
  assert_contains "$out" "END"
  assert_eq "$(grep -c '^sudo -v -p' "$CALLS")" "1" "sudo -v calls:"
  assert_contains "$(cat "$CALLS")" "sudo -v -p [glimt] password for %u: " "short, branded prompt"
}

test_require_sudo_exits_when_auth_fails() {
  local out rc=0
  out="$(SUDO_CACHED_RC=1 SUDO_AUTH_RC=1 run_lib_script "$BASH" 2>&1 <<'EOF'
glimt_require_sudo
echo SHOULD-NOT-GET-HERE
EOF
)" || rc=$?
  assert_eq "$rc" "1" "exit code:"
  assert_contains "$out" "sudo authentication failed"
  assert_not_contains "$out" "SHOULD-NOT-GET-HERE"
}

# =====================================================================
# Tests: setup.sh / setup-macos.sh argument handling (no sudo before it)
# =====================================================================
test_setup_help_exits_before_sudo() {
  local out
  out="$(with_timeout 20 /bin/bash "$ROOT/setup.sh" --help </dev/null 2>&1)" || fail "--help should exit 0: $out"
  assert_contains "$out" "Usage:"
  assert_contains "$out" "--verbose"
  assert_not_contains "$(calls)" "sudo" "sudo must not be called for --help"
}

test_setup_rejects_unknown_option_before_sudo() {
  local out rc=0
  out="$(with_timeout 20 /bin/bash "$ROOT/setup.sh" --bogus </dev/null 2>&1)" || rc=$?
  assert_eq "$rc" "1" "exit code:"
  assert_contains "$out" "Unknown option: --bogus"
  assert_not_contains "$(calls)" "sudo"
}

# =====================================================================
# Tests: confirm() in modules/fedora/lib.sh
# =====================================================================
test_confirm_answers_no_without_terminal() {
  cat >"$SB/m.sh" <<'EOF'
ask() { if printf 'y\n' | confirm "Remove x?"; then echo ANSWER=yes; else echo ANSWER=no; fi; }
EOF
  local out
  out="$(run_module_fn_abs fedora "$SB/m.sh" ask 2>&1)" || fail "$out"
  assert_contains "$out" "ANSWER=no" "piped 'y' without a terminal"
  assert_contains "$out" "non-interactive"
  out="$(GLIMT_ASSUME_YES=1 run_module_fn_abs fedora "$SB/m.sh" ask 2>&1)" || fail "$out"
  assert_contains "$out" "ANSWER=yes" "GLIMT_ASSUME_YES=1"
}

test_confirm_reads_answer_on_terminal() {
  cat >"$SB/m.sh" <<'EOF'
ask() { if confirm "Remove x?"; then echo ANSWER=yes; else echo ANSWER=no; fi; }
EOF
  local ans
  for ans in y n ""; do
    run_module_fn_abs fedora "$SB/m.sh" ask --print-driver >/dev/null 2>&1
    # type the answer after the prompt is up, and keep stdin open until then
    { sleep 1; printf '%s\n' "$ans"; sleep 3; } | in_tty "$BASH" "$SB/.driver.sh" >/dev/null 2>&1
    case "$ans" in
    y) assert_contains "$(cat "$SB/.typescript")" "ANSWER=yes" "answer 'y':" ;;
    *) assert_contains "$(cat "$SB/.typescript")" "ANSWER=no" "answer '$ans':" ;;
    esac
  done
}

# Variant of run_module_fn for files outside the repo (test fixtures).
# With --print-driver as the first arg it only writes the driver.
run_module_fn_abs() {
  local os="$1" file="$2" fn="$3"
  shift 3
  local loaded="$SB/.loaded-$(basename "$file")"
  load_definitions "$file" >"$loaded"
  cat >"$SB/.driver.sh" <<EOF
set -Eeuo pipefail
MODULE_NAME=test
source "$ROOT/modules/$os/lib.sh"
source "$ROOT/tests/trace-run-as-user.bash"
[[ "\$HOME_DIR" == "$SB" ]] || { echo "SAFETY ABORT: HOME_DIR=\$HOME_DIR" >&2; exit 99; }
source "$loaded"
$fn
EOF
  [[ "${1:-}" == --print-driver ]] && return 0
  with_timeout 20 "$BASH" "$SB/.driver.sh" </dev/null
}

# =====================================================================
# Tests: module clean actions
# =====================================================================
test_zellij_clean_succeeds_when_nothing_installed() {
  local out
  out="$(fx_run_fn install-zellij.sh clean 2>&1)" ||
    fail "clean must succeed when files are already gone (it aborted setup-extras): $out"
}

test_zellij_clean_removes_its_files_only() {
  mkdir -p "$SB/.local/bin" "$SB/.config/zellij" "$SB/.zsh/config"
  touch "$SB/.local/bin/zellij" "$SB/.zsh/config/zellij.zsh" "$SB/.zsh/config/fzf.zsh"
  # unedited config as deployed by glimt
  cp "$ROOT/modules/fedora/config/zellij.kdl" "$SB/.config/zellij/config.kdl"
  local out
  out="$(fx_run_fn install-zellij.sh clean 2>&1)" || fail "$out"
  assert_missing "$SB/.local/bin/zellij"
  assert_missing "$SB/.config/zellij"
  assert_missing "$SB/.zsh/config/zellij.zsh"
  assert_exists "$SB/.zsh/config/fzf.zsh"
}

test_claude_code_clean_keeps_user_data() {
  mkdir -p "$SB/.local/bin" "$SB/.local/share/claude" "$SB/.claude"
  touch "$SB/.local/bin/claude" "$SB/.claude/settings.json" "$SB/.claude.json"
  local out
  out="$(run_module_fn fedora modules/fedora/extras/install-claude-code.sh clean 2>&1)" || fail "$out"
  assert_missing "$SB/.local/bin/claude"
  assert_missing "$SB/.local/share/claude"
  assert_exists "$SB/.claude/settings.json"
  assert_exists "$SB/.claude.json"
}

make_zsh_tree() {
  mkdir -p "$SB/.zsh/plugins/zsh-autosuggestions" "$SB/.zsh/plugins/zsh-syntax-highlighting" \
    "$SB/.zsh/plugins/fzf-tab" "$SB/.zsh/plugins/gh" "$SB/.zsh/config"
  touch "$SB/.zsh/config/"{autosuggestions,syntax-highlighting,greeting,fzf,eza,kubectl}.zsh \
    "$SB/.zshrc" "$SB/.hushlogin"
}

assert_zsh_clean_result() {
  assert_missing "$SB/.zsh/plugins/zsh-autosuggestions"
  assert_missing "$SB/.zsh/plugins/zsh-syntax-highlighting"
  assert_missing "$SB/.zsh/config/autosuggestions.zsh"
  assert_missing "$SB/.zsh/config/syntax-highlighting.zsh"
  assert_missing "$SB/.zsh/config/greeting.zsh"
  assert_missing "$SB/.zshrc"
  # owned by other modules — must survive
  assert_exists "$SB/.zsh/plugins/fzf-tab"
  assert_exists "$SB/.zsh/plugins/gh"
  assert_exists "$SB/.zsh/config/fzf.zsh"
  assert_exists "$SB/.zsh/config/eza.zsh"
  assert_exists "$SB/.zsh/config/kubectl.zsh"
}

test_zsh_clean_fedora_keeps_other_modules_files() {
  make_zsh_tree
  local out
  out="$(run_module_fn fedora modules/fedora/install-zsh.sh clean 2>&1)" || fail "$out"
  assert_zsh_clean_result
}

test_zsh_clean_macos_keeps_other_modules_files() {
  make_zsh_tree
  local out
  out="$(run_module_fn macos modules/macos/install-zsh.sh clean 2>&1)" || fail "$out"
  assert_zsh_clean_result
  assert_missing "$SB/.hushlogin"
}

seed_gitconfig() {
  git config --global user.name "Test User"
  git config --global user.email "t@example.com"
  git config --global alias.st status
  git config --global alias.hist "log --oneline"
  git config --global alias.mine "log --author=me"
  git config --global core.pager less
}

assert_git_clean_result() {
  local cfg
  cfg="$(git config --global --list)"
  assert_not_contains "$cfg" "alias.st=" "gitconfig"
  assert_not_contains "$cfg" "alias.hist=" "gitconfig"
  assert_not_contains "$cfg" "user.name=" "gitconfig"
  assert_contains "$cfg" "alias.mine=log --author=me" "user's own alias must survive"
  assert_contains "$cfg" "core.pager=less" "unrelated settings must survive"
}

test_git_config_clean_fedora_keeps_user_aliases() {
  seed_gitconfig
  local out
  out="$(run_module_fn fedora modules/fedora/install-git-config.sh clean_git_config 2>&1)" || fail "$out"
  assert_git_clean_result
}

test_git_config_clean_macos_keeps_user_aliases() {
  seed_gitconfig
  local out
  out="$(run_module_fn macos modules/macos/install-git-config.sh clean 2>&1)" || fail "$out"
  assert_git_clean_result
}

test_eza_clean_is_non_interactive() {
  mkdir -p "$SB/.zsh/config" && touch "$SB/.zsh/config/eza.zsh"
  local out
  out="$(run_module_fn fedora modules/fedora/install-eza.sh clean 2>&1)" || fail "clean must not hang or fail without a terminal: $out"
  assert_missing "$SB/.zsh/config/eza.zsh"
  assert_not_contains "$(calls)" "dnf remove -y eza" "package removal defaults to no"
  : >"$CALLS"
  out="$(GLIMT_ASSUME_YES=1 run_module_fn fedora modules/fedora/install-eza.sh clean 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf remove -y eza" "GLIMT_ASSUME_YES=1"
}

test_gh_clean_is_non_interactive() {
  mkdir -p "$SB/.zsh/config" "$SB/.zsh/plugins/gh" && touch "$SB/.zsh/config/gh.zsh"
  local out
  out="$(run_module_fn fedora modules/fedora/install-gh.sh clean 2>&1)" || fail "$out"
  assert_missing "$SB/.zsh/config/gh.zsh"
  assert_missing "$SB/.zsh/plugins/gh"
  assert_not_contains "$(calls)" "dnf remove -y gh"
}

test_lazyvim_clean_is_non_interactive() {
  mkdir -p "$SB/.config/nvim" "$SB/.local/share/nvim"
  local out
  out="$(run_module_fn fedora modules/fedora/install-lazyvim.sh clean_lazyvim 2>&1)" || fail "$out"
  assert_missing "$SB/.config/nvim"
  assert_missing "$SB/.local/share/nvim"
  assert_not_contains "$(calls)" "dnf remove" "neovim must not be removed without consent"
}

test_pbcopy_clean_is_non_interactive() {
  mkdir -p "$SB/.local/bin" && touch "$SB/.local/bin/pbcopy" "$SB/.local/bin/pbpaste"
  local out
  out="$(RPM_INSTALLED="wl-clipboard xclip" run_module_fn fedora modules/fedora/install-pbcopy.sh clean 2>&1)" || fail "$out"
  assert_missing "$SB/.local/bin/pbcopy"
  assert_missing "$SB/.local/bin/pbpaste"
  assert_not_contains "$(calls)" "dnf remove -y xclip" "xclip removal defaults to no"
}

# =====================================================================
# Tests: PowerShell — always latest
# =====================================================================
PS_FEDORA=modules/fedora/extras/install-powershell.sh

test_powershell_fedora_installs_when_missing() {
  local out
  out="$(FAKE_UNAME_M=x86_64 RPM_INSTALLED="" run_module_fn fedora "$PS_FEDORA" install_pkg 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf install -y powershell"
  assert_not_contains "$(calls)" "dnf upgrade"
}

test_powershell_fedora_upgrades_when_present() {
  local out
  out="$(FAKE_UNAME_M=x86_64 RPM_INSTALLED="powershell" run_module_fn fedora "$PS_FEDORA" install_pkg 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf upgrade -y powershell" "re-runs must upgrade to latest"
  assert_not_contains "$(calls)" "dnf install"
}

test_powershell_fedora_skips_cleanly_on_arm() {
  local out
  out="$(FAKE_UNAME_M=aarch64 run_module_fn fedora "$PS_FEDORA" install_pkg 2>&1)" || fail "must not fail setup on aarch64: $out"
  assert_not_contains "$(calls)" "dnf " "no dnf calls on aarch64"
  assert_contains "$out" "only published for x86_64"
}

test_powershell_fedora_is_not_version_pinned() {
  assert_not_contains "$(cat "$ROOT/versions.env")" "POWERSHELL" "versions.env"
  assert_not_contains "$(cat "$ROOT/$PS_FEDORA")" "powershell-7" "module must not pin a version"
}

test_powershell_fedora_clean_removes_package() {
  local out
  out="$(run_module_fn fedora "$PS_FEDORA" clean 2>&1)" || fail "$out"
  assert_contains "$(calls)" "dnf remove -y powershell"
  assert_contains "$(calls)" "rm -f /etc/yum.repos.d/glimt-microsoft-powershell.repo"
  assert_not_contains "$(calls)" "microsoft-prod.repo" "Microsoft's own repo must be left alone"
}

# The macOS module is run end-to-end (dispatcher + guard), with brew stubbed.
run_ps_macos() {
  with_timeout 20 "$BASH" "$ROOT/modules/macos/extras/install-powershell.sh" "$1" </dev/null 2>&1
}

test_powershell_macos_installs_cask_when_missing() {
  [[ "$OS" == Darwin ]] || skip "macOS only"
  local out
  out="$(BREW_HAS_RC=1 run_ps_macos install)" || fail "$out"
  assert_contains "$(calls)" "brew install --cask --force powershell"
  assert_not_contains "$(calls)" "brew upgrade"
}

test_powershell_macos_upgrades_cask_when_present() {
  [[ "$OS" == Darwin ]] || skip "macOS only"
  local out
  out="$(BREW_HAS_RC=0 run_ps_macos install)" || fail "$out"
  assert_contains "$(calls)" "brew upgrade --cask powershell" "re-runs must upgrade to latest"
  assert_not_contains "$(calls)" "brew install"
}

test_powershell_macos_clean_uninstalls_cask() {
  [[ "$OS" == Darwin ]] || skip "macOS only"
  local out
  out="$(run_ps_macos clean)" || fail "$out"
  assert_contains "$(calls)" "brew uninstall --cask powershell"
}

# =====================================================================
# Tests: glimt CLI (update / install / clean) — runs against a throwaway repo
# =====================================================================
GLIMT_OSDIR=fedora
[[ "$OS" == Darwin ]] && GLIMT_OSDIR=macos

# fake_repo — $SB/repo with the real glimt.sh + setup-lib.sh and tiny modules
# that log how they were called to $SB/ran.
fake_repo() {
  local m="$SB/repo/modules/$GLIMT_OSDIR"
  mkdir -p "$m/extras"
  cp "$ROOT/glimt.sh" "$ROOT/setup-lib.sh" "$SB/repo/"
  printf '#!/usr/bin/env bash\necho "%s $1" >>"%s/ran"\necho %s-output\n' alpha "$SB" alpha >"$m/install-alpha.sh"
  # mentions sudo, so glimt must ask for the password up front
  printf '#!/usr/bin/env bash\nsudo true\necho "%s $1" >>"%s/ran"\n' beta "$SB" >"$m/install-beta.sh"
  printf '#!/usr/bin/env bash\necho "%s $1" >>"%s/ran"\necho gamma-boom; exit 5\n' gamma "$SB" >"$m/extras/install-gamma.sh"
  printf '#!/usr/bin/env bash\necho "%s $1" >>"%s/ran"\n' delta "$SB" >"$m/extras/install-delta.sh"
  chmod +x "$m"/install-*.sh "$m"/extras/install-*.sh
}

glimt_run() {
  REPO_DIR="$SB/repo" GLIMT_LOCK_FILE="$SB/glimt.lock" GLIMT_SKIP_PULL="${GLIMT_SKIP_PULL:-1}" \
    with_timeout 30 "$BASH" "$SB/repo/glimt.sh" "$@" </dev/null 2>&1
}

test_glimt_install_uses_progress_bar() {
  fake_repo
  local out
  out="$(glimt_run install alpha)" || fail "$out"
  assert_not_contains "$out" "alpha-output" "module output must go to the log"
  assert_contains "$out" "100% (1/1)"
  assert_eq "$(cat "$SB/ran")" "alpha all" "module call:"
  assert_not_contains "$(calls)" "sudo" "module without sudo must not prompt"
}

test_glimt_verbose_shows_module_output() {
  fake_repo
  local out
  out="$(glimt_run -v install alpha)" || fail "$out"
  assert_contains "$out" "alpha-output"
  assert_contains "$out" "Installing alpha"
  assert_not_contains "$out" "░"
  out="$(glimt_run install alpha --verbose)" || fail "$out"
  assert_contains "$out" "alpha-output" "--verbose after the action"
}

test_glimt_asks_sudo_up_front_when_needed() {
  fake_repo
  local out
  out="$(SUDO_CACHED_RC=1 SUDO_AUTH_RC=0 glimt_run install beta)" || fail "$out"
  assert_eq "$(grep -n '' "$CALLS" | grep -m1 'sudo -v' | cut -d: -f1)" "2" "sudo -v must come right after the cache check, before the module:"
  assert_contains "$(sed -n 1p "$CALLS")" "sudo -n true"
}

test_glimt_clean_runs_clean_action() {
  fake_repo
  local out
  out="$(glimt_run clean alpha)" || fail "$out"
  assert_contains "$out" "Removing alpha"
  assert_eq "$(cat "$SB/ran")" "alpha clean" "module call:"
}

test_glimt_install_failure_exits_nonzero() {
  fake_repo
  local out rc=0
  out="$(glimt_run install gamma)" || rc=$?
  assert_eq "$rc" "1" "exit code:"
  assert_contains "$out" "Installing gamma failed (exit 5)"
  assert_contains "$out" "gamma-boom" "log tail"
  assert_not_contains "$out" "An error occurred" "no duplicate ERR-trap message"
}

test_glimt_update_runs_core_and_selected_extras_in_one_bar() {
  fake_repo
  mkdir -p "$SB/.config/glimt"
  printf 'delta\n' >"$SB/.config/glimt/optional-extras.selected"
  local out
  out="$(glimt_run update)" || fail "$out"
  assert_eq "$(sed -n 1p <<<"$out")" "$(sed -n 1p <<<"$out" | grep -v modules)" "no 'Updating N modules' header:"
  assert_contains "$out" "Updating alpha"
  assert_contains "$out" "Updating delta"
  assert_contains "$out" "100% (3/3)"
  assert_eq "$(sort "$SB/ran" | tr '\n' ',')" "alpha all,beta all,delta all," "modules run:"
}

test_glimt_update_continues_with_pulled_glimt() {
  fake_repo
  # make the fake repo a clone of a local origin so `git pull` really runs
  git -C "$SB/repo" init -q -b main && git -C "$SB/repo" add -A &&
    git -C "$SB/repo" -c user.name=t -c user.email=t@t commit -qm init &&
    git clone -q --bare "$SB/repo" "$SB/origin.git" &&
    git -C "$SB/repo" remote add origin "$SB/origin.git" &&
    git -C "$SB/repo" fetch -q origin && git -C "$SB/repo" branch -q -u origin/main || fail "git setup failed"
  # a change that only exists in the pulled version of glimt.sh
  git clone -q "$SB/origin.git" "$SB/work"
  sed -i.bak 's/run_modules update "\${installers/echo "PULLED-GLIMT"; &/' "$SB/work/glimt.sh"
  git -C "$SB/work" -c user.name=t -c user.email=t@t commit -qam change && git -C "$SB/work" push -q origin main
  local out
  out="$(GLIMT_SKIP_PULL=0 glimt_run update)" || fail "$out"
  assert_contains "$out" "PULLED-GLIMT" "update must continue with the freshly pulled glimt.sh"
  assert_eq "$(grep -c '^glimt .* → ' <<<"$out")" "1" "pull count:"
  assert_not_contains "$out" "already running" "re-exec must reuse its own lock"
  # default mode: one summary line instead of git's fetch/pull/diffstat output
  assert_not_contains "$out" "glimt.sh |" "git diffstat must be hidden by default"
  assert_not_contains "$out" "Fast-forward"
  assert_not_contains "$out" "Updating repository"
}

test_glimt_update_verbose_shows_git_output() {
  fake_repo
  git -C "$SB/repo" init -q -b main && git -C "$SB/repo" add -A &&
    git -C "$SB/repo" -c user.name=t -c user.email=t@t commit -qm init &&
    git clone -q --bare "$SB/repo" "$SB/origin.git" &&
    git -C "$SB/repo" remote add origin "$SB/origin.git" &&
    git -C "$SB/repo" fetch -q origin && git -C "$SB/repo" branch -q -u origin/main || fail "git setup failed"
  local out
  out="$(GLIMT_SKIP_PULL=0 glimt_run -v update)" || fail "$out"
  assert_contains "$out" "Already up to date" "git output in verbose mode"
  assert_contains "$out" "(up to date)"
}

# Additional test files: tests/*.test.sh define more test_* functions and
# can use every helper above (run_module_fn, assertions, stubs, ...).
for f in "$ROOT"/tests/*.test.sh; do
  [[ -f "$f" ]] && source "$f"
done

# =====================================================================
# Runner
# =====================================================================
pass=0 failed=0 skipped=0 failed_names=()
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do
  [[ -n "$FILTER" && "$t" != *"$FILTER"* ]] && continue
  SB="$T/sandbox-$t"
  mkdir -p "$SB"
  out="$T/$t.out"
  (
    export SB HOME="$SB" GLIMT_TEST_HOME="$SB" CALLS="$SB/.calls"
    export GIT_CONFIG_GLOBAL="$SB/.gitconfig" GIT_CONFIG_NOSYSTEM=1
    export PATH="$STUBS:$PATH" GLIMT_LOG_DIR="$SB/logs"
    unset SUDO_ASKPASS SUDO_USER GLIMT_SUDO_KEEPALIVE_PID GLIMT_ASSUME_YES VERBOSE
    : >"$CALLS"
    cd "$SB"
    "$t"
  ) >"$out" 2>&1
  rc=$?
  if (( rc == 0 )); then
    pass=$((pass + 1))
    echo "✅ $t"
    $VERBOSE && sed 's/^/     /' "$out"
  elif (( rc == 200 )); then
    skipped=$((skipped + 1))
    echo "⏭️  $t ($(sed -n 's/^SKIP: //p' "$out"))"
  else
    failed=$((failed + 1))
    failed_names+=("$t")
    echo "❌ $t"
    sed 's/^/     /' "$out"
  fi
done

echo ""
echo "$pass passed, $failed failed, $skipped skipped"
(( failed == 0 ))
