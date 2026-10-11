#!/usr/bin/env bash
# lib.sh — shared utilities for all glimt modules
#
# Source at the top of every module (after MODULE_NAME is set):
#
#   Core modules (modules/fedora/):
#     GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
#
#   Extras modules (modules/fedora/extras/):
#     GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
#
#   source "$GLIMT_LIB"
#
# After sourcing, the following are available:
#   REAL_USER   — the user who invoked sudo (or current user)
#   HOME_DIR    — that user's home directory (via getent, never /root)
#   log/warn/die
#   run_as_user
#   deploy_config <src> <dest>  — backs up a differing dest, then copies
#   prune_backups <dest>        — keep newest $GLIMT_BACKUP_RETENTION backups
#   normalize_arch              — x86_64→amd64, aarch64→arm64
#   verify_binary <bin> [args...] — warns only, never aborts the module
#   confirm <question>          — y/N prompt; "no" when there is no terminal

# === Real user context ===
# Resolves the invoking user even when the script runs under sudo.
REAL_USER="${SUDO_USER:-$USER}"
if [[ -z "${REAL_USER}" || "${REAL_USER}" == "root" ]]; then
  REAL_USER="$(logname 2>/dev/null || echo "$USER")"
fi
HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"
HOME_DIR="${HOME_DIR:-$HOME}"

# === Logging ===
log()  { printf "[%s] %s\n"    "${MODULE_NAME:-glimt}" "$*"; }
warn() { printf "⚠️  [%s] %s\n" "${MODULE_NAME:-glimt}" "$*" >&2; }
die()  { printf "❌ [%s] %s\n"  "${MODULE_NAME:-glimt}" "$*" >&2; exit 1; }

# === Run a command as the real (non-root) user ===
# Skips sudo when already that user: modules normally run as the user, and an
# unneeded sudo could prompt for a password hidden behind the progress bar.
run_as_user() {
  if [[ $EUID -ne 0 && "$(id -un)" == "$REAL_USER" ]]; then
    "$@"
  else
    sudo -u "$REAL_USER" "$@"
  fi
}

# === Backup retention ===
#
# deploy_config writes a timestamped backup on every deployment, so re-running a
# module (or `glimt update`) accumulates one copy per run. Keep only the newest
# few. Override with GLIMT_BACKUP_RETENTION=N in the environment; 0 keeps none.
GLIMT_BACKUP_RETENTION="${GLIMT_BACKUP_RETENTION:-3}"

# === Prune old timestamped backups of a deployed config ===
#
# Usage: prune_backups <dest_file>
#
# Removes the oldest "<dest>.bak.<timestamp>" files, keeping the newest
# $GLIMT_BACKUP_RETENTION. Timestamps are fixed-width YYYYMMDDHHMMSS, so a
# lexical sort is chronological.
prune_backups() {
  local dest="$1"
  local keep="$GLIMT_BACKUP_RETENTION"
  if [[ ! "$keep" =~ ^[0-9]+$ ]]; then
    warn "GLIMT_BACKUP_RETENTION is not a number: '$keep' — keeping 3"
    keep=3
  fi

  local backups=()
  local f
  while IFS= read -r f; do
    backups+=("$f")
  done < <(find "$(dirname "$dest")" -maxdepth 1 -type f \
    -name "$(basename "$dest").bak.[0-9]*" 2>/dev/null | sort)

  local total=${#backups[@]}
  (( total > keep )) || return 0

  local remove=$(( total - keep ))
  local i
  for (( i = 0; i < remove; i++ )); do
    rm -f "${backups[i]}"
  done
  log "Pruned $remove old backup(s) of $(basename "$dest") (keeping $keep)"
}

# === Deploy a config template with automatic backup ===
#
# Usage: deploy_config <src_template> <dest_file>
#
# - Creates parent directories as needed.
# - If dest already exists AND differs from src, backs it up with a timestamp
#   before overwriting. Identical files are redeployed without a backup.
# - Sets ownership to REAL_USER:REAL_USER and mode 0644.
deploy_config() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || die "Template not found: $src"
  # Under sudo, create missing parent dirs (e.g. ~/.zsh/config) as the user,
  # not root
  if [[ $EUID -eq 0 ]]; then
    command install -d -o "$REAL_USER" -g "$REAL_USER" "$(dirname "$dest")"
  else
    mkdir -p "$(dirname "$dest")"
  fi
  # Only back up when the content actually differs. Re-running a module with an
  # unchanged template would otherwise leave an identical copy behind each time.
  # The copy below still runs unconditionally, so ownership and mode are always
  # re-applied even when nothing changed.
  if [[ -f "$dest" ]] && ! cmp -s "$src" "$dest"; then
    local backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$dest" "$backup"
    log "Backed up $(basename "$dest") → $(basename "$backup")"
    prune_backups "$dest"
  fi
  command install -o "$REAL_USER" -g "$REAL_USER" -m 0644 "$src" "$dest"
  log "Deployed $(basename "$dest")"
}

# === Normalize machine architecture to download naming convention ===
#
# Returns: amd64 | arm64  (Kubernetes / Go-binary ecosystem standard)
# Usage:   arch="$(normalize_arch)"
normalize_arch() {
  case "$(uname -m)" in
    x86_64)  echo "amd64" ;;
    aarch64) echo "arm64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

# === Verify a binary is working after install ===
#
# Usage: verify_binary <binary> [args...]
#
# Passes any extra args to the binary (e.g. "--version").
# Prints a warning (does not exit) on failure so setup can continue.
verify_binary() {
  local bin="$1"; shift
  # Always return 0: modules run under set -e, so a non-zero return would
  # abort the module (skipping config) instead of just warning.
  if ! command -v "$bin" >/dev/null 2>&1; then
    warn "$bin not found in PATH after install"
    return 0
  fi
  if [[ $# -gt 0 ]] && ! "$bin" "$@" >/dev/null 2>&1; then
    warn "$bin found but '$bin $*' failed"
    return 0
  fi
  log "✅ $bin OK"
}

# === Interactive y/N prompt that is safe without a terminal ===
# setup-extras / glimt clean run modules behind a progress bar with output
# going to a log file, where a `read` prompt would be invisible and hang (or
# fail under set -e). Without a terminal, answer "no" — unless
# GLIMT_ASSUME_YES=1 is set.
confirm() {
  local question="$1" reply=""
  if [[ "${GLIMT_ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 || ! -t 1 ]]; then
    log "$question → no (non-interactive)"
    return 1
  fi
  read -rp "$question [y/N]: " reply || return 1
  [[ "$reply" =~ ^[Yy]$ ]]
}
