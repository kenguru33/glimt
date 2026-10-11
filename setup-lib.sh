#!/usr/bin/env bash
# Shared helpers for the setup orchestrators (setup.sh, setup-extras.sh,
# setup-macos.sh, setup-macos-extras.sh). Sourced, never run directly.
#
# Keep this Bash 3.2 compatible (no declare -A, no mapfile): setup.sh starts
# under macOS's /bin/bash before it delegates to setup-macos.sh.
#
# Provides:
#   glimt_needs_sudo <script>... — may these modules run sudo (incl. via brew)?
#   glimt_require_sudo     — ask for the sudo password once, keep it alive
#   glimt_cleanup          — remove temp files; call from the caller's EXIT trap
#   progress_init <total>  — start a progress bar over <total> steps
#   progress_run <title> <cmd...>
#                          — run one step: progress bar by default, full
#                            output when VERBOSE=true. Never aborts the caller;
#                            failures are collected and shown by progress_finish
#   progress_finish        — print the final bar and a failure summary
#   glimt_banner [subtitle] — clear the screen and print the glimt header
#   glimt_versions         — print "name<TAB>version" for everything installed
#   glimt_changes <before> <after>
#                          — print what was updated/installed/removed between
#                            two glimt_versions snapshots

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

# glimt_needs_sudo <script>... — may any of these modules call sudo? Directly,
# or indirectly: Homebrew casks and mas run sudo themselves (e.g. a cask with a
# .pkg or a root-owned app), and that prompt would be hidden by the bar.
glimt_needs_sudo() {
  grep -qE 'sudo|mas_|--cask|brew_cask_install' "$@" 2>/dev/null
}

# Files to delete when the orchestrator exits; callers run glimt_cleanup from
# their EXIT trap.
GLIMT_CLEANUP_FILES=()
glimt_cleanup() {
  if (( ${#GLIMT_CLEANUP_FILES[@]} > 0 )); then rm -f "${GLIMT_CLEANUP_FILES[@]}" 2>/dev/null; fi
  return 0
}

# macOS: Homebrew calls `sudo` itself, from inside the progress bar, and macOS
# keeps the sudo timestamp per terminal, so a cached credential is not enough.
# Ask once and hand the password to every later sudo through SUDO_ASKPASS:
# glimt's macOS lib runs `sudo -A`, and Homebrew uses -A when SUDO_ASKPASS is set.
_glimt_askpass_setup() {
  if [[ -n "${SUDO_ASKPASS:-}" && -x "${SUDO_ASKPASS:-}" ]]; then return 0; fi
  local pw_file askpass pw tries=0
  pw_file="$(mktemp -t glimt-sudo)"
  askpass="$(mktemp -t glimt-askpass)"
  GLIMT_CLEANUP_FILES+=("$pw_file" "$askpass")
  chmod 600 "$pw_file"
  chmod 700 "$askpass"
  printf '#!/bin/sh\ncat %q\n' "$pw_file" >"$askpass"
  while true; do
    printf '[glimt] password for %s: ' "$(id -un)" >&2
    IFS= read -rs pw <"${GLIMT_TTY:-/dev/tty}" || pw=""
    echo >&2
    printf '%s\n' "$pw" >"$pw_file"
    pw=""
    if sudo -S -p '' -v <"$pw_file" 2>/dev/null; then break; fi
    tries=$(( tries + 1 ))
    if (( tries >= 3 )); then echo "glimt: sudo authentication failed" >&2; exit 1; fi
    echo "Sorry, try again." >&2
  done
  export SUDO_ASKPASS="$askpass"
}

glimt_require_sudo() {
  if [[ "${GLIMT_OS:-$(uname -s)}" == "Darwin" ]]; then
    _glimt_askpass_setup
  elif ! sudo -n true 2>/dev/null; then
    sudo -v -p "[glimt] password for %u: " || { echo "glimt: sudo authentication failed" >&2; exit 1; }
  fi
  glimt_sudo_keepalive
}

# === What changed: version snapshots before and after a run ===
# Package managers report versions; binaries glimt downloads into ~/.local/bin
# have no common way to ask, so a checksum stands in ("#..." = changed build).
glimt_versions() {
  {
    if [[ "${GLIMT_OS:-$(uname -s)}" == "Darwin" ]]; then
      if command -v brew >/dev/null 2>&1; then
        brew list --formula --versions 2>/dev/null | awk '{print $1"\t"$NF}'
        brew list --cask --versions 2>/dev/null | awk '{print $1"\t"$NF}'
      fi
      if command -v mas >/dev/null 2>&1; then
        # "937984704  Amphetamine  (5.3.2)" → "Amphetamine<TAB>5.3.2"
        mas list 2>/dev/null | sed -E 's/^ *[0-9]+ +(.*[^ ]) +\(([^)]*)\) *$/\1	\2/' | grep "$(printf '\t')"
      fi
    else
      if command -v rpm >/dev/null 2>&1; then
        rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}\n' 2>/dev/null
      fi
      if command -v flatpak >/dev/null 2>&1; then
        flatpak list --app --columns=name,version 2>/dev/null | awk -F'\t' 'NF {print $1"\t"($2 == "" ? "-" : $2)}'
      fi
    fi
    local f
    for f in "$HOME/.local/bin"/*; do
      if [[ -f "$f" && -x "$f" ]]; then
        printf '%s\t#%s\n' "${f##*/}" "$(cksum <"$f" | cut -d' ' -f1)"
      fi
    done
  } | awk -F'\t' 'NF == 2 { v[$1] = ($1 in v) ? v[$1] "," $2 : $2 } END { for (k in v) print k "\t" v[k] }' | sort
  return 0
}

# glimt_changes <before> <after> — lines "U<TAB>name<TAB>old<TAB>new",
# "A<TAB>name<TAB>new", "R<TAB>name<TAB>old"
_glimt_diff_versions() {
  awk -F'\t' 'NR == FNR { a[$1] = $2; next } { b[$1] = $2 }
    END {
      for (k in b) if (!(k in a)) print "A\t" k "\t" b[k]; else if (a[k] != b[k]) print "U\t" k "\t" a[k] "\t" b[k]
      for (k in a) if (!(k in b)) print "R\t" k "\t" a[k]
    }' "$1" "$2" | sort -t "$(printf '\t')" -k1,1 -k2,2
}

# Print a short summary; the full list goes to $GLIMT_LOG_DIR/changes.txt
glimt_changes() {
  local diff max=12
  diff="$(_glimt_diff_versions "$1" "$2")"
  echo
  if [[ -z "$diff" ]]; then
    echo "Everything is up to date."
    return 0
  fi
  mkdir -p "$GLIMT_LOG_DIR"
  printf '%s\n' "$diff" >"$GLIMT_LOG_DIR/changes.txt"
  local kind title n
  for kind in U A R; do
    case "$kind" in U) title="Updated" ;; A) title="Installed" ;; R) title="Removed" ;; esac
    n="$(printf '%s\n' "$diff" | grep -c "^$kind")" || true
    (( n > 0 )) || continue
    if command -v gum >/dev/null 2>&1; then gum style --bold "$title"; else echo "$title"; fi
    printf '%s\n' "$diff" | grep "^$kind" | head -n "$max" | awk -F'\t' '
      function v(x) { return (x ~ /^#/) ? "new build" : x }
      $1 == "U" { if ($3 ~ /^#/) printf "  %-28s new build\n", $2; else printf "  %-28s %s → %s\n", $2, $3, $4 }
      $1 == "A" { printf "  %-28s %s\n", $2, v($3) }
      $1 == "R" { printf "  %s\n", $2 }'
    if (( n > max )); then echo "  … and $(( n - max )) more ($GLIMT_LOG_DIR/changes.txt)"; fi
  done
}

# === Header ===
# glimt_banner [subtitle] →
#
#   glimt  Fedora post-install setup
#   e1e4a84 · Fedora Linux 43 · bernt@laptop
#   ────────────────────────────────────────
_glimt_os_name() {
  if [[ "${GLIMT_OS:-$(uname -s)}" == "Darwin" ]]; then
    echo "macOS $(sw_vers -productVersion 2>/dev/null)"
  elif [[ -r /etc/os-release ]]; then
    ( . /etc/os-release && echo "${PRETTY_NAME:-${NAME:-Linux}}" )
  else
    uname -s
  fi
}

glimt_banner() {
  local subtitle="${1:-}" root rev meta rule
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  rev="$(git -C "$root" rev-parse --short HEAD 2>/dev/null)" || rev=""
  meta="${rev:+$rev · }$(_glimt_os_name) · $(id -un)@$(hostname -s 2>/dev/null || hostname)"
  printf -v rule '%*s' 40 ''
  rule="${rule// /─}"
  clear 2>/dev/null || true
  echo
  if [[ -z "${NO_COLOR:-}" ]] && _progress_tty; then
    printf '  \033[1mglimt\033[0m%s\n' "${subtitle:+  $subtitle}"
    printf '  \033[2m%s\033[0m\n' "$meta"
    printf '  \033[2m%s\033[0m\n' "$rule"
  else
    printf '  glimt%s\n  %s\n  %s\n' "${subtitle:+  $subtitle}" "$meta" "$rule"
  fi
  echo
  return 0
}

# Section heading inside a run, e.g. "Core modules"
glimt_section() {
  echo
  if command -v gum >/dev/null 2>&1; then gum style --bold "$1"; else echo "$1"; fi
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
  PROGRESS_START=$SECONDS
  mkdir -p "$GLIMT_LOG_DIR"
}

progress_run() {
  local title="$1"
  shift
  local log rc=0
  log="$GLIMT_LOG_DIR/$(printf '%s' "$title" | tr -c 'A-Za-z0-9._-' '_').log"

  if [[ "${VERBOSE:-false}" == "true" ]]; then
    echo "==> $title"
    "$@" || rc=$?
    if (( rc != 0 )); then echo "✗ $title failed (exit $rc)" >&2; fi
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
      echo "✗ $title failed (exit $rc)" >&2
      tail -n 15 "$log" 2>/dev/null | sed 's/^/  │ /' >&2
    fi
  fi
  return 0
}

progress_finish() {
  local secs=$(( SECONDS - ${PROGRESS_START:-$SECONDS} )) took
  if (( secs >= 60 )); then took="$(( secs / 60 ))m $(( secs % 60 ))s"; else took="${secs}s"; fi
  if (( ${#PROGRESS_FAILED[@]} > 0 )); then
    local names
    names="$(printf '%s, ' "${PROGRESS_FAILED[@]}")"
    [[ "${VERBOSE:-false}" == "true" ]] || echo "$(_progress_bar "$PROGRESS_DONE" "$PROGRESS_TOTAL")  ${#PROGRESS_FAILED[@]} failed"
    echo "Failed: ${names%, }" >&2
    echo "Logs:   $GLIMT_LOG_DIR" >&2
  elif [[ "${VERBOSE:-false}" != "true" ]]; then
    echo "$(_progress_bar "$PROGRESS_DONE" "$PROGRESS_TOTAL")  done in $took"
  else
    echo "Done in $took"
  fi
}
