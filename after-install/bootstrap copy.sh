#!/usr/bin/env bash
set -e
trap 'echo "❌ An error occurred. Exiting." >&2' ERR

SCRIPT_NAME="bootstrap.sh"
REPO_URL="https://github.com/kenguru33/glimt.git"
REPO_DIR="$HOME/.glimt"
REAL_USER="$(logname 2>/dev/null || echo "$USER")"
ACTION="all"
VERBOSE=0
GUM_VERSION="0.14.3"
BRANCH="main"        # Default branch

# === Theme / color flags ===
THEME_AUTO=1
THEME_OVERRIDE=""    # "light" | "dark" | ""
NO_COLOR=0

# === Parse arguments ===
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    branch=*) BRANCH="${arg#branch=}" ;;
    --light) THEME_AUTO=0; THEME_OVERRIDE="light" ;;
    --dark)  THEME_AUTO=0; THEME_OVERRIDE="dark" ;;
    --no-color) NO_COLOR=1 ;;
    *)
      echo "❌ Unknown argument: $arg"
      echo "Usage: $SCRIPT_NAME [--verbose] [branch=branchname] [--light|--dark] [--no-color]"
      exit 1
      ;;
  esac
done

# === Verbose helper ===
run() {
  if [[ "$VERBOSE" -eq 1 ]]; then
    "$@"
  else
    "$@" >/dev/null 2>&1
  fi
}

[[ "$VERBOSE" -eq 1 ]] && {
  echo "🔍 Verbose mode enabled"
  echo "🌿 Using branch: $BRANCH"
}

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Could not detect OS."
  exit 1
fi

# === Prevent root execution ===
if [ "$(id -u)" -eq 0 ]; then
  echo "❌ Do not run as root. Use a normal user."
  exit 1
fi

# === Color / palette helpers ===
_supports_color() {
  [[ -t 1 ]] && [[ "$NO_COLOR" -eq 0 ]] && [[ -z "${NO_COLOR_ENV:-${NO_COLOR}}" ]]
}

_detect_bg_theme() {
  # explicit override
  if [[ -n "$THEME_OVERRIDE" ]]; then
    echo "$THEME_OVERRIDE"; return
  fi
  # heuristic via COLORFGBG (common in many terminals)
  if [[ -n "$COLORFGBG" ]]; then
    local bg="${COLORFGBG##*;}"
    if [[ "$bg" =~ ^[0-9]+$ ]]; then
      (( bg >= 8 )) && { echo "light"; return; } || { echo "dark"; return; }
    fi
  fi
  # fallback
  echo "dark"
}

_set_palette() {
  if ! _supports_color; then
    CYAN=""; GOLD=""; WHITE=""; DIM=""; RESET=""
    return
  fi

  local theme="$(_detect_bg_theme)"

  if [[ "$theme" == "light" ]]; then
    # light background: darker inks
    CYAN="\033[1;36m"     # bold cyan
    GOLD="\033[33m"       # normal yellow/gold
    WHITE="\033[30m"      # black (for readable body text)
    DIM="\033[2m"
    RESET="\033[0m"
  else
    # dark background: bright inks
    CYAN="\033[1;96m"     # bright cyan
    GOLD="\033[1;93m"     # bright yellow/gold
    WHITE="\033[1;97m"    # bright white
    DIM="\033[2m"
    RESET="\033[0m"
  fi
}

print_banner() {
  clear || true
  _set_palette
  local theme="$(_detect_bg_theme)"

  echo -e "
      ${GOLD}🌟   ✨${RESET}
   ${GOLD}✨${RESET}   ${CYAN}G L A N S${RESET}     ${GOLD}🌟${RESET}
       ${GOLD}✨${RESET}  ${WHITE}The Final Shine for Fresh Installs${RESET}

    ${WHITE}Installs essential tools and configurations${RESET}
    ${WHITE}Optimizes settings with minimal system changes${RESET}
    ${WHITE}Uses sudo only when absolutely necessary${RESET}

    ${CYAN}OS:${RESET}     ${WHITE}$OS_ID${RESET}
    ${CYAN}Branch:${RESET} ${WHITE}$BRANCH${RESET}
    ${CYAN}Theme:${RESET}  ${WHITE}${theme}${RESET}${DIM} (override with --light/--dark)${RESET}
"
}

# === Require sudo (install philosophy) ===
require_sudo() {
  _set_palette
  echo -e "    ${CYAN}💡 Install Philosophy${RESET}
    ${WHITE}• Work in \$HOME when possible${RESET}
    ${WHITE}• Use sudo only if no user-space option exists${RESET}
    ${WHITE}• Keep changes safe and reversible${RESET}
    ${WHITE}• Be transparent about actions taken${RESET}
"
  echo -e "    ${CYAN}🔑 Sudo Access${RESET}"
  echo -e "    ${WHITE}Needed for installing packages or small system tweaks.${RESET}\n"

  # Use /dev/tty to avoid accidental non-interactive cancellation
  read -rp "    Proceed with setup? [y/N]: " confirm </dev/tty || true
  case "$confirm" in
    [yY][eE][sS]|[yY])
      echo ""
      echo -e "    ${CYAN}🛡 Enter Your Sudo Password${RESET}"
      echo -e "    ${WHITE}This is required to continue setup...${RESET}"
      echo ""
      ;;
    *)
      echo -e "    ${GOLD}⚠️ Setup cancelled by user.${RESET}"
      exit 0
      ;;
  esac

  if ! sudo -v >/dev/null 2>&1; then
    echo ""
    echo -e "    ${GOLD}🚫 Sudo unavailable or authentication failed for '$REAL_USER'.${RESET}

    ${CYAN}🛠 If you need sudo:${RESET}
    ${WHITE}1) su -${RESET}
    ${WHITE}2) usermod -aG sudo $REAL_USER${RESET}
    ${WHITE}3) Log out/in (or reboot)${RESET}
"
    exit 1
  fi
}

# === INSTALL: clone or update repo ===
install_repo() {
  if ! command -v git >/dev/null 2>&1; then
    echo "📦 Installing git..."
    if command -v apt-get >/dev/null 2>&1; then
      run sudo apt-get update
      run sudo apt-get install -y git
    else
      echo "❌ 'git' is required but not found, and apt-get is unavailable."
      exit 1
    fi
  fi

  echo "📥 Cloning or updating glimt repo (branch: $BRANCH)..."
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
  if [[ ! -f "setup.sh" ]]; then
    echo "❌ setup.sh not found in $REPO_DIR"
    ls -la "$REPO_DIR"
    exit 1
  fi
  bash setup.sh
}

# === MAIN ===
print_banner
require_sudo
install_repo
run_installer
