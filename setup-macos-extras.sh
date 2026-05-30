#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Optional extras setup failed." >&2' ERR

VERBOSE=false
for arg in "$@"; do
  case "$arg" in
  --verbose) VERBOSE=true ;;
  --quiet)   VERBOSE=false ;;
  esac
done

GLIMT_ROOT="${GLIMT_ROOT:-$HOME/.glimt}"
MODULE_DIR="$GLIMT_ROOT/modules/macos/extras"
STATE_FILE="$HOME/.config/glimt/optional-extras.selected"
mkdir -p "$(dirname "$STATE_FILE")"

declare -A MODULES=(
  [chatgpt]="chatgpt"
  ["claude-code"]="claude"
  ["claude-desktop"]="/Applications/Claude.app"
  [discord]="/Applications/Discord.app"
  [dotnet]="dotnet"
  ["jetbrains-toolbox"]="/Applications/JetBrains Toolbox.app"
  [lens]="/Applications/Lens.app"
  [notion]="/Applications/Notion.app"
  [spotify]="/Applications/Spotify.app"
  [tableplus]="/Applications/TablePlus.app"
  [ytmusic]="/Applications/YouTube Music.app"
  [vscode]="code"
)

declare -A MODULE_DESCRIPTIONS=(
  [chatgpt]="ChatGPT desktop app"
  [discord]="Discord"
  ["claude-code"]="Claude Code CLI"
  ["claude-desktop"]="Claude desktop app"
  [dotnet]=".NET SDK"
  ["jetbrains-toolbox"]="JetBrains Toolbox (manages Rider and other IDEs)"
  [lens]="Lens Kubernetes IDE"
  [notion]="Notion"
  [spotify]="Spotify"
  [tableplus]="TablePlus database client"
  [vscode]="Visual Studio Code"
  [ytmusic]="YouTube Music"
)

module_installed() {
  local name="$1"
  local bin="${MODULES[$name]}"
  if [[ "$bin" == /* ]]; then
    [[ -e "$bin" ]]
  else
    command -v "$bin" &>/dev/null
  fi
}

run_with_spinner() {
  local title="$1"; shift
  if command -v gum &>/dev/null && [[ -t 1 && -t 2 ]]; then
    gum spin --spinner dot --title "$title" -- bash -c '"$@" >/dev/null 2>&1' _ "$@" || "$@"
  else
    echo "▶️  $title"
    "$@"
  fi
}

run_module() {
  local name="$1"
  local mode="$2"
  local script="$MODULE_DIR/install-$name.sh"

  [[ -f "$script" ]] || { echo "⚠️  Missing $script"; return; }
  [[ -x "$script" ]] || chmod +x "$script"

  if [[ "$mode" == "clean" ]]; then
    echo "🧹 Cleaning $name..."
    bash "$script" clean >/dev/null
    gum style --foreground 10 "✔️  install-$name.sh cleaned"
    return
  fi

  if $VERBOSE; then
    echo "▶️  Running install-$name.sh"
    bash "$script" all
    echo "✔️  install-$name.sh finished"
  else
    run_with_spinner "Running $name..." bash "$script" all
    gum style --foreground 10 "✔️  install-$name.sh finished"
  fi
}

main() {
  declare -A PREV=()
  if [[ -f "$STATE_FILE" ]]; then
    while read -r m; do
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

  IFS=$'\n' read -r -d '' -a selected < <(
    printf "%s\n" "${menu[@]}" | sort |
      gum choose --no-limit --height=15 "${preselect[@]}" && printf '\0'
  )

  declare -A WANT=()
  for s in "${selected[@]}"; do
    for m in "${map[@]}"; do
      [[ "$m" == "$s:"* ]] && WANT["${m#*:}"]=1
    done
  done

  for m in "${!MODULES[@]}"; do
    now="${WANT[$m]:-}"
    before="${PREV[$m]:-}"

    if [[ "$now" == "1" && "$before" != "1" ]] && ! module_installed "$m"; then
      run_module "$m" all
    elif [[ "$now" != "1" && "$before" == "1" ]]; then
      run_module "$m" clean
    fi
  done

  printf "%s\n" "${!WANT[@]}" >"$STATE_FILE"
}

main
