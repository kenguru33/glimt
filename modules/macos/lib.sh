#!/usr/bin/env bash
# lib.sh — shared utilities for all glimt macOS modules
#
# Source at the top of every module (after MODULE_NAME is set):
#
#   GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
#   source "$GLIMT_LIB"
#
# After sourcing, the following are available:
#   REAL_USER   — the invoking user (SUDO_USER if run via sudo, otherwise USER)
#   HOME_DIR    — that user's home directory
#   log/warn/die
#   run_as_user — runs as REAL_USER; no-op wrapper when already that user
#   deploy_config <src> <dest>
#   verify_binary <bin> [args...]
#   normalize_arch

# === Real user context ===
REAL_USER="${SUDO_USER:-$USER}"
if [[ -z "${REAL_USER}" || "${REAL_USER}" == "root" ]]; then
  REAL_USER="$(id -un)"
fi
# macOS has no getent; dscl is the canonical way to read user records
HOME_DIR=$(dscl . -read /Users/"$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
HOME_DIR="${HOME_DIR:-$(eval echo "~$REAL_USER")}"

# === Logging ===
log()  { printf "[%s] %s\n"    "${MODULE_NAME:-glimt}" "$*"; }
warn() { printf "⚠️  [%s] %s\n" "${MODULE_NAME:-glimt}" "$*" >&2; }
die()  { printf "❌ [%s] %s\n"  "${MODULE_NAME:-glimt}" "$*" >&2; exit 1; }

# === sudo wrapper: use askpass when the orchestrator provides one ===
# setup-macos.sh captures the password once and exports SUDO_ASKPASS. Modules
# run under a gum spinner still have a controlling terminal, so plain sudo would
# prompt there — and that prompt is hidden by the spinner, hanging setup. The -A
# flag forces sudo to read the password from SUDO_ASKPASS instead of any tty.
# When SUDO_ASKPASS is unset (e.g. running a module standalone), fall back to
# normal interactive sudo.
sudo() {
  if [[ -n "${SUDO_ASKPASS:-}" ]]; then
    command sudo -A "$@"
  else
    command sudo "$@"
  fi
}

# === Run a command as the real (non-root) user ===
# When already running as that user (typical macOS), executes directly.
run_as_user() {
  if [[ "$(id -u)" == "0" ]]; then
    sudo -u "$REAL_USER" "$@"
  else
    "$@"
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
# Creates parent directories, backs up any existing dest with a timestamp
# (only when its content differs from src), then copies src to dest with
# mode 0644.
deploy_config() {
  local src="$1" dest="$2"
  [[ -f "$src" ]] || die "Template not found: $src"
  mkdir -p "$(dirname "$dest")"
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
  cp "$src" "$dest"
  chmod 644 "$dest"
  log "Deployed $(basename "$dest")"
}

# === Normalize machine architecture to download naming convention ===
#
# Returns: amd64 | arm64  (Go / Kubernetes ecosystem standard)
# macOS Apple Silicon reports arm64 natively (unlike Linux which says aarch64).
normalize_arch() {
  case "$(uname -m)" in
    x86_64)         echo "amd64" ;;
    arm64|aarch64)  echo "arm64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

# === Install a brew cask, skipping if already installed or app exists ===
#
# Usage: brew_cask_install <cask> [/Applications/App.app]
# Checks brew registration and optional app path before installing.
brew_cask_install() {
  local cask="$1"
  local app_path="${2:-}"
  if brew list --cask "$cask" &>/dev/null; then
    log "$cask already managed by brew."
  elif [[ -n "$app_path" && -e "$app_path" ]]; then
    log "$cask already installed at $app_path."
  else
    brew install --cask --force "$cask"
  fi
}

# === Install an app from the Mac App Store via mas ===
#
# Usage: mas_install <apple_id> <app_name>
# Installs mas if missing, then installs the app if not already present.
mas_install() {
  local apple_id="$1"
  local app_name="${2:-App $1}"
  if ! command -v mas &>/dev/null; then
    brew install mas
  fi
  if mas list 2>/dev/null | grep -q "^${apple_id} "; then
    log "$app_name already installed from App Store."
  else
    # mas 7+ requires root privileges to install apps.
    sudo mas install "$apple_id"
  fi
}

# === Uninstall an App Store app via mas ===
#
# Usage: mas_uninstall <apple_id>
mas_uninstall() {
  local apple_id="$1"
  if command -v mas &>/dev/null; then
    sudo mas uninstall "$apple_id" 2>/dev/null || true
  fi
}

# === Verify a binary is working after install ===
#
# Usage: verify_binary <binary> [args...]
# Warns (does not exit) on failure so setup can continue.
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
