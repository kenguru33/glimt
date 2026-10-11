#!/usr/bin/env bash
# Use env bash (not /bin/bash) — macOS ships Bash 3.2, but this script uses
# mapfile (Bash 4+). Homebrew's bash is first on PATH after setup.
set -euo pipefail
trap 'echo "Error: glimt failed at: $BASH_COMMAND" >&2' ERR

# === Config ===
SCRIPT_NAME="glimt"
REPO_DIR="${REPO_DIR:-$HOME/.glimt}"
if [[ "$(uname -s)" == "Darwin" ]]; then
  EXTRA_SCRIPT="$REPO_DIR/setup-macos-extras.sh"
else
  EXTRA_SCRIPT="$REPO_DIR/setup-extras.sh"
fi
SETUP_SCRIPT="$REPO_DIR/setup.sh"
LOCK_FILE="${GLIMT_LOCK_FILE:-/tmp/.glimt.lock}"
VALID_ACTIONS=("update" "module-selection" "install" "clean")

if [[ "$(uname -s)" == "Darwin" ]]; then
  MODULES_DIR="$REPO_DIR/modules/macos"
else
  MODULES_DIR="$REPO_DIR/modules/fedora"
fi

# === Helpers ===
print_usage() {
  cat <<EOF
Usage: $SCRIPT_NAME [-v|--verbose] <action> [args...]

Actions:
  update [all|module] → git pull, then run all core modules + selected extras (or only <module> if provided)
  install <module>    → run modules/fedora/**/install-<module>.sh with 'all'
  clean <module>      → run modules/fedora/**/install-<module>.sh with 'clean'
  module-selection    → run setup-extras.sh (optional modules UI)

Options:
  -v, --verbose       → show every module's full output instead of the progress bar

Note: <module> is the installer basename without "install-" and ".sh".
EOF
}

# setup-lib.sh may not be loaded yet (or at all) when the trap fires
glimt_exit_cleanup() {
  if declare -F glimt_cleanup >/dev/null; then glimt_cleanup; fi
}

acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local pid
    pid=$(<"$LOCK_FILE")
    # Same PID = this process re-exec'd itself after `update` pulled a new glimt
    if [[ "$pid" == "$$" ]]; then
      trap 'rm -f "$LOCK_FILE"; glimt_exit_cleanup' EXIT
      return 0
    fi
    if kill -0 "$pid" 2>/dev/null; then
      echo "glimt is already running (PID $pid). If not, remove $LOCK_FILE" >&2
      exit 1
    fi
    rm -f "$LOCK_FILE"
  fi
  echo "$$" >"$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"; glimt_exit_cleanup' EXIT
}

ensure_repo() {
  if [[ ! -d "$REPO_DIR" ]]; then
    echo "Error: $REPO_DIR not found (clone glimt there first)" >&2
    exit 1
  fi
}

find_module_script() {
  local module="$1"
  find "$MODULES_DIR" -type f -name "install-$module.sh" -print -quit 2>/dev/null || true
}

# === Extras state: the optional modules glimt manages ===
STATE_FILE="$HOME/.config/glimt/optional-extras.selected"

# is_extra <script> — is this an optional (extras) module?
is_extra() { [[ "$1" == "$MODULES_DIR/extras/"* ]]; }

state_add() {
  mkdir -p "$(dirname "$STATE_FILE")"
  grep -qxF "$1" "$STATE_FILE" 2>/dev/null || echo "$1" >>"$STATE_FILE"
}

state_remove() {
  [[ -f "$STATE_FILE" ]] || return 0
  local tmp="$STATE_FILE.tmp"
  grep -vxF "$1" "$STATE_FILE" >"$tmp" || true
  mv "$tmp" "$STATE_FILE"
}

# === Progress bar + sudo (shared with the setup scripts) ===
load_setup_lib() {
  [[ -z "${GLIMT_SETUP_LIB_LOADED:-}" ]] || return 0
  GLIMT_SETUP_LIB_LOADED=1
  if [[ -f "$REPO_DIR/setup-lib.sh" ]]; then
    # shellcheck source=setup-lib.sh
    source "$REPO_DIR/setup-lib.sh"
  else
    # Older checkout without setup-lib.sh: run modules with plain output
    VERBOSE=true
    PROGRESS_FAILED=()
    glimt_require_sudo() { :; }
    glimt_needs_sudo() { return 1; }
    progress_init() { PROGRESS_FAILED=(); }
    progress_run() { local t="$1"; shift; echo "==> $t"; "$@" || PROGRESS_FAILED+=("$t"); }
    progress_finish() { :; }
    glimt_versions() { :; }
    glimt_changes() { :; }
  fi
}

# module_label <script> — install-k9s.sh → k9s
module_label() {
  local name
  name="$(basename "$1" .sh)"
  echo "${name#install-}"
}

# run_modules <install|update|clean> <script>... — runs installers behind the progress bar
# (full output with -v). Asks for sudo once up front if any of them needs it,
# so no password prompt can hide behind the bar. Fails if any module failed.
run_modules() {
  local mode="$1"
  shift
  (( $# > 0 )) || return 0
  local script
  for script in "$@"; do
    [[ -f "$script" ]] || { echo "Error: installer not found: $script" >&2; exit 1; }
    [[ -x "$script" ]] || chmod +x "$script"
  done

  load_setup_lib
  if glimt_needs_sudo "$@"; then
    glimt_require_sudo
  fi

  cd "$REPO_DIR"
  progress_init "$#"
  for script in "$@"; do
    case "$mode" in
      clean)  progress_run "Removing $(module_label "$script")" bash "$script" clean ;;
      update) progress_run "Updating $(module_label "$script")" bash "$script" all ;;
      *)      progress_run "Installing $(module_label "$script")" bash "$script" all ;;
    esac
  done
  progress_finish
  if [[ -n "${GLIMT_VERSIONS_BEFORE:-}" ]]; then
    glimt_versions >"$GLIMT_LOG_DIR/versions-after.txt"
    glimt_changes "$GLIMT_VERSIONS_BEFORE" "$GLIMT_LOG_DIR/versions-after.txt"
  fi
  # exit (not return) so the ERR trap doesn't add a confusing second message
  if (( ${#PROGRESS_FAILED[@]} > 0 )); then exit 1; fi
}

# === Actions ===
run_update() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  if [[ "${GLIMT_SKIP_PULL:-0}" != "1" ]]; then
    local before after
    before="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
    if $VERBOSE; then
      git -C "$REPO_DIR" fetch --all --prune
      git -C "$REPO_DIR" pull --rebase --stat
    else
      # Quiet by default; git's own error output still shows if the pull fails
      git -C "$REPO_DIR" fetch --all --prune --quiet
      git -C "$REPO_DIR" pull --rebase --quiet
    fi
    after="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
    if [[ "$before" == "$after" ]]; then
      echo "glimt $after (up to date)"
    else
      echo "glimt $before → $after"
    fi

    local bin_target="$HOME/.local/bin/glimt"
    if [[ -f "$bin_target" ]]; then
      cp "$REPO_DIR/glimt.sh" "$bin_target"
      chmod +x "$bin_target"
    fi

    # Continue with the freshly pulled glimt, so changes to this script take
    # effect in this same run instead of the next one.
    local verbose_flag=()
    $VERBOSE && verbose_flag=(--verbose)
    GLIMT_SKIP_PULL=1 exec bash "$REPO_DIR/glimt.sh" "${verbose_flag[@]+"${verbose_flag[@]}"}" update "$@"
  fi

  load_setup_lib
  prepare_update

  local maybe_module="${1:-}"
  [[ "$maybe_module" == "all" ]] && maybe_module=""
  if [[ -n "$maybe_module" ]]; then
    local script
    script="$(find_module_script "$maybe_module")"
    [[ -n "$script" ]] || { echo "Error: unknown module: $maybe_module" >&2; exit 1; }
    run_modules update "$script"
  else
    # Core modules + selected extras, all under one progress bar
    local installers=()
    mapfile -t installers < <(find "$MODULES_DIR" -maxdepth 1 -type f -name 'install-*.sh' -print 2>/dev/null | sort)
    if (( ${#installers[@]} == 0 )); then
      echo "Warning: no modules found in $MODULES_DIR" >&2
    fi

    # Selected extras — but only those still installed: an extra removed by
    # hand (or by an older `glimt clean`) is dropped, not reinstalled
    if [[ -s "$STATE_FILE" ]]; then
      local selected=() installed=() module
      mapfile -t selected < <(grep -v '^[[:space:]]*$' "$STATE_FILE")
      if (( ${#selected[@]} > 0 )); then
        local found
        if found="$(bash "$EXTRA_SCRIPT" installed "${selected[@]}" 2>/dev/null)"; then
          mapfile -t installed <<<"$found"
        else
          # Can't tell what is installed: keep the old behaviour, update all
          installed=("${selected[@]}")
        fi
      fi
      for module in "${selected[@]+"${selected[@]}"}"; do
        local extra_script="$MODULES_DIR/extras/install-$module.sh"
        if [[ ! -f "$extra_script" ]]; then
          echo "Warning: extras module not found: $module" >&2
        elif [[ " ${installed[*]-} " == *" $module "* ]]; then
          installers+=("$extra_script")
        else
          echo "Skipping $module: not installed (run 'glimt install $module' to add it back)"
          state_remove "$module"
        fi
      done
    fi

    run_modules update "${installers[@]+"${installers[@]}"}"
  fi
}

# Before an update: refresh package metadata once (so modules can tell what is
# outdated without each one hitting the network) and record installed versions
# for the summary at the end.
prepare_update() {
  if [[ "$(uname -s)" == "Darwin" ]] && command -v brew >/dev/null 2>&1; then
    if $VERBOSE; then
      brew update
    elif [[ -t 1 ]] && command -v gum >/dev/null 2>&1; then
      gum spin --spinner dot --title "Checking for updates" -- brew update --quiet >/dev/null 2>&1 || true
    else
      brew update --quiet >/dev/null 2>&1 || true
    fi
    export HOMEBREW_NO_AUTO_UPDATE=1
    GLIMT_BREW_OUTDATED="$(brew outdated --quiet 2>/dev/null | tr '\n' ' ')" || GLIMT_BREW_OUTDATED=""
    export GLIMT_BREW_OUTDATED
  fi
  mkdir -p "$GLIMT_LOG_DIR"
  GLIMT_VERSIONS_BEFORE="$GLIMT_LOG_DIR/versions-before.txt"
  glimt_versions >"$GLIMT_VERSIONS_BEFORE"
}

run_install() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  local module="${1:-}"
  [[ -n "$module" ]] || { echo "Usage: $SCRIPT_NAME install <module>"; exit 2; }
  local script; script="$(find_module_script "$module")"
  [[ -n "$script" ]] || { echo "Error: unknown module: $module" >&2; exit 1; }
  run_modules install "$script"
  if is_extra "$script"; then state_add "$module"; fi
}

run_clean() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  local module="${1:-}"
  [[ -n "$module" ]] || { echo "Usage: $SCRIPT_NAME clean <module>"; exit 2; }
  local script; script="$(find_module_script "$module")"
  [[ -n "$script" ]] || { echo "Error: unknown module: $module" >&2; exit 1; }
  run_modules clean "$script"
  if is_extra "$script"; then state_remove "$module"; fi
}

run_module_selection() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  if [[ -x "$EXTRA_SCRIPT" ]]; then
    if $VERBOSE; then
      ( cd "$REPO_DIR" && bash "$EXTRA_SCRIPT" --verbose all )
    else
      ( cd "$REPO_DIR" && bash "$EXTRA_SCRIPT" all )
    fi
  else
    echo "Error: not found or not executable: $EXTRA_SCRIPT" >&2
    exit 1
  fi
}

# === Entry Point ===
# -v/--verbose may appear anywhere; everything else is <action> [args...]
VERBOSE=false
ARGS=()
for arg in "$@"; do
  case "$arg" in
    -v | --verbose) VERBOSE=true ;;
    *) ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

ACTION="${1:-}"
shift || true

case "$ACTION" in
  update)            run_update "$@" ;;
  install)           run_install "${1:-}" ;;
  clean)             run_clean "${1:-}" ;;
  module-selection)  run_module_selection ;;
  *)                 print_usage; exit 1 ;;
esac
