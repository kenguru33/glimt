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
#   deploy_config <src> <dest>
#   verify_binary <bin> [args...]

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
run_as_user() { sudo -u "$REAL_USER" "$@"; }

# === Deploy a config template with automatic backup ===
#
# Usage: deploy_config <src_template> <dest_file>
#
# - Creates parent directories as needed.
# - If dest already exists, backs it up with a timestamp before overwriting.
# - Sets ownership to REAL_USER:REAL_USER and mode 0644.
deploy_config() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || die "Template not found: $src"
  mkdir -p "$(dirname "$dest")"
  if [[ -f "$dest" ]]; then
    local backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$dest" "$backup"
    log "Backed up $(basename "$dest") → $(basename "$backup")"
  fi
  install -o "$REAL_USER" -g "$REAL_USER" -m 0644 "$src" "$dest"
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
  if ! command -v "$bin" >/dev/null 2>&1; then
    warn "$bin not found in PATH after install"
    return 1
  fi
  if [[ $# -gt 0 ]] && ! "$bin" "$@" >/dev/null 2>&1; then
    warn "$bin found but '$bin $*' failed"
    return 1
  fi
  log "✅ $bin OK"
}
