#!/usr/bin/env bash
set -Eeo pipefail
trap 'echo "Error: bootstrap failed at line $LINENO: $BASH_COMMAND" >&2' ERR

SCRIPT_NAME="bootstrap.sh"
REPO_URL="https://github.com/kenguru33/glimt.git"
REPO_DIR="$HOME/.glimt"
REAL_USER="$(logname 2>/dev/null || echo "$USER")"
ACTION="all"
VERBOSE=0
GUM_VERSION="0.14.3"
BRANCH="main" # Default branch

# === Theme / color flags ===
THEME_AUTO=1
THEME_OVERRIDE="" # "light" | "dark" | ""
NO_COLOR=0

# === Parse arguments ===
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    branch=*)     BRANCH="${arg#branch=}" ;;
    --light)      THEME_AUTO=0; THEME_OVERRIDE="light" ;;
    --dark)       THEME_AUTO=0; THEME_OVERRIDE="dark"  ;;
    --no-color)   NO_COLOR=1 ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $SCRIPT_NAME [--verbose] [branch=branchname] [--light|--dark] [--no-color]"
      exit 1
      ;;
  esac
done

[[ "$VERBOSE" -eq 1 ]] && {
  echo "Verbose mode, branch: $BRANCH"
}

# === Detect OS ===
if [[ "$(uname -s)" == "Darwin" ]]; then
  OS_ID="macos"
  OS_ID_LIKE=""
elif [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
  OS_ID_LIKE="${ID_LIKE:-}"
else
  echo "Error: cannot detect OS" >&2
  exit 1
fi

if [[ "$OS_ID" != "fedora" && "$OS_ID_LIKE" != *"fedora"* && "$OS_ID" != "rhel" && "$OS_ID" != "macos" ]]; then
  echo "Error: unsupported OS '$OS_ID' (glimt requires Fedora, RHEL or macOS)" >&2
  exit 1
fi

# === Prevent root execution ===
if [[ "$(id -u)" -eq 0 ]] && [[ "$OS_ID" != "macos" ]]; then
  echo "Error: do not run as root; use a normal user" >&2
  exit 1
fi

# === Color / palette helpers ===
_supports_color() {
  [[ -t 1 ]] && [[ "$NO_COLOR" -eq 0 ]] && [[ -z "${NO_COLOR_ENV:-${NO_COLOR}}" ]]
}

_detect_bg_theme() {
  if [[ -n "$THEME_OVERRIDE" ]]; then
    echo "$THEME_OVERRIDE"; return
  fi
  if [[ -n "$COLORFGBG" ]]; then
    local bg="${COLORFGBG##*;}"
    if [[ "$bg" =~ ^[0-9]+$ ]]; then
      (( bg >= 8 )) && { echo "light"; return; } || { echo "dark"; return; }
    fi
  fi
  echo "dark"
}

_set_palette() {
  if ! _supports_color; then
    CYAN=""; GOLD=""; WHITE=""; DIM=""; RESET=""
    return
  fi
  local theme="$(_detect_bg_theme)"
  if [[ "$theme" == "light" ]]; then
    CYAN="\033[1;36m"; GOLD="\033[33m";    WHITE="\033[30m";  DIM="\033[2m"; RESET="\033[0m"
  else
    CYAN="\033[1;96m"; GOLD="\033[1;93m";  WHITE="\033[1;97m"; DIM="\033[2m"; RESET="\033[0m"
  fi
}

print_banner() {
  clear || true
  _set_palette
  echo -e "
  ${CYAN}glimt${RESET}
  ${DIM}Post-install setup for Fedora and macOS${RESET}

  ${DIM}OS${RESET}      $OS_ID
  ${DIM}Branch${RESET}  $BRANCH
"
}

# === Quiet runner: silent on success; on failure, show the real stderr ===
run() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    "$@"
  else
    if ! "$@" 1>/dev/null; then
      echo "Error: command failed: $*" >&2
      # Re-run without stdout suppression so you see the error/stderr
      "$@"
      exit 1
    fi
  fi
}

# === Require sudo (install philosophy) ===
# On macOS, sudo is not required for Homebrew installs — skip the prompt.
require_sudo() {
  if [[ "$OS_ID" == "macos" ]]; then
    return 0
  fi
  # Use /dev/tty to avoid accidental non-interactive cancellation
  read -rp "  Continue? [y/N] " confirm </dev/tty || true
  case "$confirm" in
    [yY][eE][sS]|[yY]) ;;
    *) echo "  Cancelled."; exit 0 ;;
  esac

  if ! sudo -v -p "  [glimt] password for %u: "; then
    echo "Error: sudo failed for '$REAL_USER'. glimt needs a user with sudo rights." >&2
    exit 1
  fi
}

# === Ensure git is available ===
# On macOS, /usr/bin/git is a stub that exists even without the Command Line
# Tools, so `command -v git` is not a reliable check — use `xcode-select -p`,
# which only succeeds once the CLT (or Xcode) is actually installed.
ensure_git() {
  if [[ "$OS_ID" == "macos" ]]; then
    if xcode-select -p >/dev/null 2>&1; then
      return 0
    fi
    echo "Installing Xcode Command Line Tools (needed for git)."
    echo "Click \"Install\" in the macOS dialog and accept the license."
    xcode-select --install >/dev/null 2>&1 || true
    until xcode-select -p >/dev/null 2>&1; do
      sleep 5
    done

    # git ships with the CLT — confirm it is actually functional before we rely on it.
    if ! git --version >/dev/null 2>&1; then
      echo "Error: git is still unavailable. Run 'xcode-select --install' (or" >&2
      echo "'sudo xcode-select --reset && xcode-select --install'), then re-run bootstrap." >&2
      exit 1
    fi
  elif ! command -v git >/dev/null 2>&1; then
    run sudo dnf install -y git
  fi
}

# === INSTALL: clone or update repo ===
install_repo() {
  ensure_git

  echo "Fetching glimt ($BRANCH)..."
  if [[ -d "$REPO_DIR/.git" ]]; then
    run git -C "$REPO_DIR" fetch origin
    run git -C "$REPO_DIR" checkout "$BRANCH"
    run git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
  else
    run git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
  fi
}

# === RUN: launch installer ===
run_installer() {
  cd "$REPO_DIR"
  local setup_script="setup.sh"
  [[ "$OS_ID" == "macos" ]] && setup_script="setup-macos.sh"

  if [[ ! -f "$setup_script" ]]; then
    echo "Error: $setup_script not found in $REPO_DIR" >&2
    ls -la "$REPO_DIR"
    exit 1
  fi
  if [[ "$VERBOSE" -eq 1 ]]; then
    bash "$setup_script" --verbose
  else
    bash "$setup_script"
  fi
}

# === MAIN ===
print_banner
require_sudo
install_repo
run_installer
