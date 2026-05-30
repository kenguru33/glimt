#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Optional extras setup failed." >&2' ERR

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
# Module registry
# value: path starting with / → file/dir existence check
#        anything else        → command-v check
# -----------------------------
declare -A MODULES=(
  [chatgpt]="/Applications/ChatGPT.app"
  ["claude-code"]="claude"
  ["claude-desktop"]="/Applications/Claude.app"
  [discord]="/Applications/Discord.app"
  [dotnet]="$HOME/.dotnet/dotnet"
  ["jetbrains-toolbox"]="/Applications/JetBrains Toolbox.app"
  [lens]="/Applications/Lens.app"
  [notion]="/Applications/Notion.app"
  [spotify]="/Applications/Spotify.app"
  [tableplus]="/Applications/TablePlus.app"
  [vscode]="/Applications/Visual Studio Code.app"
  [ytmusic]="/Applications/YouTube Music.app"
)

declare -A MODULE_DESCRIPTIONS=(
  [chatgpt]="ChatGPT desktop app"
  ["claude-code"]="Claude Code CLI"
  ["claude-desktop"]="Claude desktop app"
  [discord]="Discord"
  [dotnet]=".NET SDK / Runtime"
  ["jetbrains-toolbox"]="JetBrains Toolbox"
  [lens]="Lens Kubernetes IDE"
  [notion]="Notion"
  [spotify]="Spotify"
  [tableplus]="TablePlus"
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
  local title="$1"
  shift
  if command -v gum &>/dev/null && [[ -t 1 && -t 2 ]]; then
    gum spin --spinner dot --title "$title" -- bash -c '"$@" >/dev/null 2>&1' _ "$@" || "$@"
  else
    echo "▶️  $title"
    "$@"
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
  local name="$1"
  local mode="$2"
  local script="$MODULE_DIR/install-$name.sh"

  [[ -f "$script" ]] || { echo "⚠️  Missing $script"; return; }
  [[ -x "$script" ]] || chmod +x "$script"

  if [[ "$mode" == "clean" ]]; then
    echo "🧹 Cleaning $name…"
    bash "$script" clean >/dev/null
    gum_style_ok "✔️  install-$name.sh cleaned"
    return
  fi

  if $VERBOSE; then
    echo "▶️  Running install-$name.sh"
    bash "$script" all
    echo "✔️  install-$name.sh finished"
  else
    run_with_spinner "Running $name…" bash "$script" all
    gum_style_ok "✔️  install-$name.sh finished"
  fi
}

# -----------------------------
# Main
# -----------------------------
main() {
  declare -A PREV=()
  if [[ -f "$STATE_FILE" ]]; then
    while IFS= read -r m; do
      [[ -n "$m" ]] && PREV["$m"]=1
    done <"$STATE_FILE"
  fi

  menu=()
  map=()
  preselect=()

  for m in "${!MODULES[@]}"; do
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

  # gum choose exits non-zero when the user presses Escape; treat that as
  # "no change" by letting read consume an empty stream (|| true guards set -e).
  selected=()
  IFS=$'\n' read -r -d '' -a selected < <(
    printf "%s\n" "${menu[@]}" | sort |
      gum choose --no-limit --height=15 "${preselect[@]}" && printf '\0'
  ) || true

  declare -A WANT=()
  for s in "${selected[@]}"; do
    for entry in "${map[@]}"; do
      [[ "$entry" == "$s:"* ]] && WANT["${entry#*:}"]=1
    done
  done

  for m in "${!MODULES[@]}"; do
    now="${WANT[$m]:-}"
    before="${PREV[$m]:-}"

    if [[ "$now" == "1" && "$before" != "1" ]]; then
      run_module "$m" all
    elif [[ "$now" != "1" && "$before" == "1" ]]; then
      run_module "$m" clean
    fi
  done

  printf "%s\n" "${!WANT[@]}" >"$STATE_FILE"
}

main
