#!/usr/bin/env bash
# Shared helpers for the setup orchestrators (setup.sh, setup-extras.sh,
# setup-macos.sh, setup-macos-extras.sh). Sourced, never run directly.
#
# Keep this Bash 3.2 compatible (no declare -A, no mapfile): setup.sh starts
# under macOS's /bin/bash before it delegates to setup-macos.sh.
#
# Provides:
#   glimt_require_sudo     — ask for the sudo password once, keep it alive
#   progress_init <total>  — start a progress bar over <total> steps
#   progress_run <title> <cmd...>
#                          — run one step: progress bar by default, full
#                            output when VERBOSE=true. Never aborts the caller;
#                            failures are collected and shown by progress_finish
#   progress_finish        — print the final bar and a failure summary

# === sudo: ask once, keep the credential warm for the whole run ===
# Module output is hidden behind the progress bar, so a sudo prompt that
# appears mid-run (because the 5-minute timestamp expired) would be invisible
# and hang the install. Ask up front, then refresh the timestamp in the
# background until the orchestrator exits.
glimt_sudo_keepalive() {
  if [[ -n "${GLIMT_SUDO_KEEPALIVE_PID:-}" ]] && kill -0 "$GLIMT_SUDO_KEEPALIVE_PID" 2>/dev/null; then
    return 0
  fi
  local parent=$$
  (
    while kill -0 "$parent" 2>/dev/null; do
      sudo -n -v 2>/dev/null || true
      sleep 50
    done
  ) >/dev/null 2>&1 &
  GLIMT_SUDO_KEEPALIVE_PID=$!
  export GLIMT_SUDO_KEEPALIVE_PID
}

glimt_require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    echo "🔐 Glimt needs administrator access. Enter your password once — it is kept for the whole run."
    sudo -v || { echo "❌ sudo authentication failed." >&2; exit 1; }
  fi
  glimt_sudo_keepalive
}

# === Progress bar ===
GLIMT_LOG_DIR="${GLIMT_LOG_DIR:-$HOME/.cache/glimt/logs/$(date +%Y%m%d-%H%M%S)}"
export GLIMT_LOG_DIR
PROGRESS_TOTAL=0
PROGRESS_DONE=0
PROGRESS_FAILED=()

# Use gum's spinner + bar only on a real terminal; otherwise print plain lines.
_progress_tty() {
  [[ "${GLIMT_DISABLE_SPIN:-0}" != "1" && -t 1 && -t 2 && -n "${TERM:-}" && "${TERM:-}" != "dumb" ]]
}

# _progress_bar <done> <total> → "███████░░░░░░░  45% (9/20)"
_progress_bar() {
  local done=$1 total=$2 width=30 filled pct bar empty
  (( total > 0 )) || total=1
  filled=$(( done * width / total ))
  pct=$(( done * 100 / total ))
  printf -v bar '%*s' "$filled" ''
  printf -v empty '%*s' "$(( width - filled ))" ''
  printf '%s%s %3d%% (%d/%d)' "${bar// /█}" "${empty// /░}" "$pct" "$done" "$total"
}

progress_init() {
  PROGRESS_TOTAL=$1
  PROGRESS_DONE=0
  PROGRESS_FAILED=()
  mkdir -p "$GLIMT_LOG_DIR"
}

progress_run() {
  local title="$1"
  shift
  local log rc=0
  log="$GLIMT_LOG_DIR/$(printf '%s' "$title" | tr -c 'A-Za-z0-9._-' '_').log"

  if [[ "${VERBOSE:-false}" == "true" ]]; then
    echo "▶️  $title"
    "$@" || rc=$?
    if (( rc == 0 )); then echo "✅ Finished: $title"; else echo "❌ Failed: $title (exit $rc)" >&2; fi
  elif _progress_tty && command -v gum >/dev/null 2>&1; then
    gum spin --spinner dot --title "$(_progress_bar "$PROGRESS_DONE" "$PROGRESS_TOTAL")  $title" -- \
      bash -c 'log=$1; shift; "$@" >"$log" 2>&1' _ "$log" "$@" || rc=$?
  elif _progress_tty; then
    printf '\r\033[K%s  %s' "$(_progress_bar "$PROGRESS_DONE" "$PROGRESS_TOTAL")" "$title"
    "$@" >"$log" 2>&1 || rc=$?
    printf '\r\033[K'
  else
    echo "[$(( PROGRESS_DONE + 1 ))/$PROGRESS_TOTAL] $title"
    "$@" >"$log" 2>&1 || rc=$?
  fi

  PROGRESS_DONE=$(( PROGRESS_DONE + 1 ))
  if (( rc != 0 )); then
    PROGRESS_FAILED+=("$title")
    if [[ "${VERBOSE:-false}" != "true" ]]; then
      echo "❌ $title failed (exit $rc) — last lines of $log:" >&2
      tail -n 15 "$log" 2>/dev/null | sed 's/^/   │ /' >&2
    fi
  fi
  return 0
}

progress_finish() {
  if [[ "${VERBOSE:-false}" != "true" ]]; then
    echo "$(_progress_bar "$PROGRESS_DONE" "$PROGRESS_TOTAL")"
  fi
  if (( ${#PROGRESS_FAILED[@]} > 0 )); then
    echo "⚠️  ${#PROGRESS_FAILED[@]} step(s) failed:" >&2
    printf '   • %s\n' "${PROGRESS_FAILED[@]}" >&2
    echo "   Logs: $GLIMT_LOG_DIR" >&2
  fi
}
