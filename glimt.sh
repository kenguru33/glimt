#!/usr/bin/env bash
# Use env bash (not /bin/bash) — macOS ships Bash 3.2, but this script uses
# mapfile (Bash 4+). Homebrew's bash is first on PATH after setup.
set -euo pipefail
trap 'echo "❌ An error occurred at: $BASH_COMMAND" >&2' ERR

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

acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local pid
    pid=$(<"$LOCK_FILE")
    # Same PID = this process re-exec'd itself after `update` pulled a new glimt
    if [[ "$pid" == "$$" ]]; then
      trap 'rm -f "$LOCK_FILE"' EXIT
      return 0
    fi
    if kill -0 "$pid" 2>/dev/null; then
      echo "🔒 Glimt is already running (PID $pid)"
      echo "If this is an error, delete the lock file and retry:"
      echo "  rm -f $LOCK_FILE"
      exit 1
    fi
    echo "⚠️  Removing stale lock (PID $pid no longer running)"
    rm -f "$LOCK_FILE"
  fi
  echo "$$" >"$LOCK_FILE"
  trap 'rm -f "$LOCK_FILE"' EXIT
}

ensure_repo() {
  if [[ ! -d "$REPO_DIR" ]]; then
    echo "❌ Repo directory not found: $REPO_DIR"
    echo "   Clone your repo there, e.g.:"
    echo "   git clone <url> \"$REPO_DIR\""
    exit 1
  fi
}

find_module_script() {
  local module="$1"
  find "$MODULES_DIR" -type f -name "install-$module.sh" -print -quit 2>/dev/null || true
}

# === Progress bar + sudo (shared with the setup scripts) ===
load_setup_lib() {
  if [[ -f "$REPO_DIR/setup-lib.sh" ]]; then
    # shellcheck source=setup-lib.sh
    source "$REPO_DIR/setup-lib.sh"
  else
    # Older checkout without setup-lib.sh: run modules with plain output
    VERBOSE=true
    PROGRESS_FAILED=()
    glimt_require_sudo() { :; }
    progress_init() { PROGRESS_FAILED=(); }
    progress_run() { local t="$1"; shift; echo "▶️  $t"; "$@" || PROGRESS_FAILED+=("$t"); }
    progress_finish() { :; }
  fi
}

# run_modules <all|clean> <script>... — runs installers behind the progress bar
# (full output with -v). Asks for sudo once up front if any of them needs it,
# so no password prompt can hide behind the bar. Fails if any module failed.
run_modules() {
  local mode="$1"
  shift
  (( $# > 0 )) || return 0
  local script
  for script in "$@"; do
    [[ -f "$script" ]] || { echo "❌ Installer not found: $script"; exit 1; }
    [[ -x "$script" ]] || chmod +x "$script"
  done

  load_setup_lib
  if grep -qE 'sudo|mas_' "$@" 2>/dev/null; then
    glimt_require_sudo
  fi

  cd "$REPO_DIR"
  progress_init "$#"
  for script in "$@"; do
    if [[ "$mode" == "clean" ]]; then
      progress_run "Removing $(basename "$script")" bash "$script" clean
    else
      progress_run "$(basename "$script")" bash "$script" all
    fi
  done
  progress_finish
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
      echo "🔄 Updating repository in $REPO_DIR..."
      git -C "$REPO_DIR" fetch --all --prune
      git -C "$REPO_DIR" pull --rebase --stat
    else
      # Quiet by default; git's own error output still shows if the pull fails
      git -C "$REPO_DIR" fetch --all --prune --quiet
      git -C "$REPO_DIR" pull --rebase --quiet
    fi
    after="$(git -C "$REPO_DIR" rev-parse --short HEAD)"
    if [[ "$before" == "$after" ]]; then
      echo "✅ glimt is up to date ($after)"
    else
      echo "✅ glimt updated $before → $after"
    fi

    local bin_target="$HOME/.local/bin/glimt"
    if [[ -f "$bin_target" ]]; then
      cp "$REPO_DIR/glimt.sh" "$bin_target"
      chmod +x "$bin_target"
      $VERBOSE && echo "✅ glimt binary updated"
    fi

    # Continue with the freshly pulled glimt, so changes to this script take
    # effect in this same run instead of the next one.
    local verbose_flag=()
    $VERBOSE && verbose_flag=(--verbose)
    GLIMT_SKIP_PULL=1 exec bash "$REPO_DIR/glimt.sh" "${verbose_flag[@]+"${verbose_flag[@]}"}" update "$@"
  fi

  local maybe_module="${1:-}"
  [[ "$maybe_module" == "all" ]] && maybe_module=""
  if [[ -n "$maybe_module" ]]; then
    local script
    script="$(find_module_script "$maybe_module")"
    [[ -n "$script" ]] || { echo "❌ Module not found: $maybe_module"; exit 1; }
    run_modules all "$script"
  else
    # Core modules + selected extras, all under one progress bar
    local installers=()
    mapfile -t installers < <(find "$MODULES_DIR" -maxdepth 1 -type f -name 'install-*.sh' -print 2>/dev/null | sort)
    if (( ${#installers[@]} == 0 )); then
      echo "ℹ️  No core installers found under: $MODULES_DIR"
    fi

    local state_file="$HOME/.config/glimt/optional-extras.selected"
    if [[ -f "$state_file" ]]; then
      while IFS= read -r module; do
        [[ -n "$module" ]] || continue
        local extra_script="$MODULES_DIR/extras/install-$module.sh"
        if [[ -f "$extra_script" ]]; then
          installers+=("$extra_script")
        else
          echo "⚠️  Extras module script not found: $module"
        fi
      done < "$state_file"
    fi

    echo "🚀 Running ${#installers[@]} modules..."
    run_modules all "${installers[@]+"${installers[@]}"}"
  fi
}

run_install() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  local module="${1:-}"
  [[ -n "$module" ]] || { echo "Usage: $SCRIPT_NAME install <module>"; exit 2; }
  local script; script="$(find_module_script "$module")"
  [[ -n "$script" ]] || { echo "❌ Module not found: $module"; exit 1; }
  run_modules all "$script"
}

run_clean() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  local module="${1:-}"
  [[ -n "$module" ]] || { echo "Usage: $SCRIPT_NAME clean <module>"; exit 2; }
  local script; script="$(find_module_script "$module")"
  [[ -n "$script" ]] || { echo "❌ Module not found: $module"; exit 1; }
  run_modules clean "$script"
}

run_module_selection() {
  acquire_lock
  ensure_repo
  export GLIMT_ROOT="$REPO_DIR"

  echo "🎛️ Running module selection..."
  if [[ -x "$EXTRA_SCRIPT" ]]; then
    if $VERBOSE; then
      ( cd "$REPO_DIR" && bash "$EXTRA_SCRIPT" --verbose all )
    else
      ( cd "$REPO_DIR" && bash "$EXTRA_SCRIPT" all )
    fi
  else
    echo "❌ Missing or non-executable: $EXTRA_SCRIPT"
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
