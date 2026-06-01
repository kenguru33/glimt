#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Optional extras setup failed at line $LINENO: $BASH_COMMAND" >&2' ERR

# -----------------------------
# Args
# -----------------------------
VERBOSE=false
ACTION="all"

for arg in "$@"; do
  case "$arg" in
  --verbose) VERBOSE=true ;;
  --quiet)   VERBOSE=false ;;
  all | install) ACTION="$arg" ;;
  *)
    echo "❌ Unknown argument: $arg"
    exit 1
    ;;
  esac
done

# -----------------------------
# Paths
# -----------------------------
GLIMT_ROOT="${GLIMT_ROOT:-$HOME/.glimt}"
MODULE_DIR="$GLIMT_ROOT/modules/macos/extras"
STATE_FILE="$HOME/.config/glimt/optional-extras.selected"
mkdir -p "$(dirname "$STATE_FILE")"

# -----------------------------
# OS guard
# -----------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "❌ setup-macos-extras.sh requires macOS."
  exit 1
fi

# -----------------------------
# Ensure a modern Bash
# macOS ships Bash 3.2, but this script uses associative arrays (Bash 4+).
# It may be launched by /bin/bash (e.g. via `glimt module-selection`), so
# re-exec under Homebrew's bash when needed.
# -----------------------------
if (( BASH_VERSINFO[0] < 4 )); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    if [[ -x "$_b" && -z "${GLIMT_EXTRAS_REEXEC:-}" ]]; then
      export GLIMT_EXTRAS_REEXEC=1
      exec "$_b" "$0" "$@"
    fi
  done
  echo "❌ This script needs Bash 4+. Install it with: brew install bash" >&2
  exit 1
fi

# -----------------------------
# Module registry
# ORDERED_MODULES drives iteration; avoids ${!assoc[@]} nameref regression in bash 5.3.
# MODULES value: path starting with / → file/dir existence check
#               anything else        → command-v check
# -----------------------------
ORDERED_MODULES=(
  1password
  1password-cli
  amphetamine
  chatgpt
  claude-code
  claude-desktop
  discord
  docker
  dotnet
  jetbrains-toolbox
  lens
  magnet
  notion
  spotify
  tableplus
  things
  teams
  vscode
  ytmusic
)

declare -A MODULES=(
  [1password]="/Applications/1Password.app"
  [1password-cli]="op"
  [amphetamine]="/Applications/Amphetamine.app"
  [chatgpt]="/Applications/ChatGPT.app"
  [claude-code]="claude"
  [claude-desktop]="/Applications/Claude.app"
  [discord]="/Applications/Discord.app"
  [docker]="/Applications/Docker.app"
  [dotnet]="$HOME/.dotnet/dotnet"
  [jetbrains-toolbox]="/Applications/JetBrains Toolbox.app"
  [lens]="/Applications/Lens.app"
  [magnet]="/Applications/Magnet.app"
  [notion]="/Applications/Notion.app"
  [spotify]="/Applications/Spotify.app"
  [tableplus]="/Applications/TablePlus.app"
  [things]="/Applications/Things3.app"
  [teams]="/Applications/Microsoft Teams.app"
  [vscode]="/Applications/Visual Studio Code.app"
  [ytmusic]="/Applications/YouTube Music.app"
)

declare -A MODULE_DESCRIPTIONS=(
  [1password]="1Password password manager"
  [1password-cli]="1Password CLI (op)"
  [amphetamine]="Amphetamine keep-awake utility"
  [chatgpt]="ChatGPT desktop app"
  [claude-code]="Claude Code CLI"
  [claude-desktop]="Claude desktop app"
  [discord]="Discord"
  [docker]="Docker Desktop"
  [dotnet]=".NET SDK / Runtime"
  [jetbrains-toolbox]="JetBrains Toolbox"
  [lens]="Lens Kubernetes IDE"
  [magnet]="Magnet window manager"
  [notion]="Notion"
  [spotify]="Spotify"
  [tableplus]="TablePlus"
  [things]="Things 3 task manager"
  [teams]="Microsoft Teams"
  [vscode]="Visual Studio Code"
  [ytmusic]="YouTube Music"
)

# -----------------------------
# Detection (UX only)
# -----------------------------
module_installed() {
  local check="${MODULES[$1]}"
  if [[ "$check" == /* ]]; then
    [[ -e "$check" ]]
  else
    command -v "$check" &>/dev/null
  fi
}

# -----------------------------
# Spinner (install only)
# -----------------------------
run_with_spinner() {
  if command -v gum &>/dev/null && [[ -t 1 && -t 2 ]]; then
    gum spin --spinner dot --title "$1" -- bash -c '"$@" >/dev/null 2>&1' _ "${@:2}" || "${@:2}"
  else
    echo "▶️  $1"
    "${@:2}"
  fi
}

gum_style_ok() {
  if command -v gum &>/dev/null; then
    gum style --foreground 10 "$1"
  else
    echo "$1"
  fi
}

# -----------------------------
# Run module
# -----------------------------
run_module() {
  [[ -n "${1:-}" ]] || { echo "⚠️  run_module called without a module name"; return 1; }
  [[ -f "$MODULE_DIR/install-$1.sh" ]] || { echo "⚠️  Missing $MODULE_DIR/install-$1.sh"; return; }
  [[ -x "$MODULE_DIR/install-$1.sh" ]] || chmod +x "$MODULE_DIR/install-$1.sh"

  if [[ "${2:-all}" == "clean" ]]; then
    echo "🧹 Cleaning $1…"
    bash "$MODULE_DIR/install-$1.sh" clean >/dev/null
    gum_style_ok "✔️  install-$1.sh cleaned"
    return
  fi

  if [[ "$VERBOSE" == "true" ]]; then
    echo "▶️  Running install-$1.sh"
    bash "$MODULE_DIR/install-$1.sh" all
    echo "✔️  install-$1.sh finished"
  else
    run_with_spinner "Running $1…" bash "$MODULE_DIR/install-$1.sh" all
    gum_style_ok "✔️  install-$1.sh finished"
  fi
}

# -----------------------------
# Main
# -----------------------------
main() {



  declare -A PREV=()
  if [[ -f "$STATE_FILE" ]]; then
    while IFS= read -r m; do
      if [[ -n "$m" ]]; then PREV["$m"]=1; fi
    done <"$STATE_FILE"
  fi

  menu=()
  map=()
  preselect=()

  for m in "${ORDERED_MODULES[@]}"; do
    if [[ "${PREV[$m]:-}" != "1" ]] && module_installed "$m"; then
      label="$m – ${MODULE_DESCRIPTIONS[$m]} [not managed by glimt]"
    else
      label="$m – ${MODULE_DESCRIPTIONS[$m]}"
    fi
    menu+=("$label")
    map+=("$label:$m")

    if [[ "${PREV[$m]:-}" == "1" ]] || module_installed "$m"; then
      preselect+=(--selected "$label")
    fi
  done

  # Capture gum output and exit code separately so Escape = no-op.
  gum_output=""
  gum_output=$(printf "%s\n" "${menu[@]}" | sort | gum choose --no-limit --height=$(( ${#menu[@]} + 2 )) "${preselect[@]}") || return 0

  selected=()
  if [[ -n "$gum_output" ]]; then
    mapfile -t selected <<< "$gum_output"
  fi

  declare -A WANT=()
  for s in "${selected[@]}"; do
    for entry in "${map[@]}"; do
      if [[ "$entry" == "$s:"* ]]; then WANT["${entry#*:}"]=1; fi
    done
  done

  # === Clear and restore header before installs begin ===
  clear
  gum style --foreground 220 --bold "🌟  G L I M T  —  Optional Extras"
  echo ""

  for m in "${ORDERED_MODULES[@]}"; do
    now="${WANT[$m]:-}"
    before="${PREV[$m]:-}"

    if [[ "$now" == "1" && "$before" != "1" ]]; then
      run_module "$m" all
    elif [[ "$now" != "1" && "$before" == "1" ]]; then
      run_module "$m" clean
    fi
  done

  for m in "${ORDERED_MODULES[@]}"; do
    if [[ "${WANT[$m]:-}" == "1" ]]; then printf "%s\n" "$m"; fi
  done >"$STATE_FILE"
}

main
