#!/bin/bash
# Glimt module: nerdfonts
# Actions: all | deps | install | config | clean

set -uo pipefail
trap 'cleanup_temp' EXIT

MODULE_NAME="nerdfonts"
ACTION="${1:-all}"

HOME_DIR="$HOME"
FONT_DIR="$HOME_DIR/.local/share/fonts"
CACHE_DIR="$HOME_DIR/.cache/glimt"
TMP_DIR="$CACHE_DIR/nerdfonts-$$"
FONT_CACHE_LOG="$CACHE_DIR/fc-cache.log"

cleanup_temp() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR" 2>/dev/null || true
}

# Font definitions
declare -A FONTS
FONTS=(
  ["Hack"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/Hack.zip"
  ["FiraCode"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip"
  ["JetBrainsMono"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip"
)

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_user() {
  if [[ "$EUID" -eq 0 ]]; then
    echo "❌ Do not run this module as root." >&2
    exit 1
  fi
}

deps() {
  log "📦 Checking dependencies..."

  local missing_deps=()

  # Check for download tool
  if ! command -v wget &>/dev/null 2>&1 && ! command -v curl &>/dev/null 2>&1; then
    missing_deps+=("wget")
  fi

  # Check for unzip
  if ! command -v unzip &>/dev/null 2>&1; then
    missing_deps+=("unzip")
  fi

  # fontconfig is already installed on Silverblue, no need to check

  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log "⚠️  Missing dependencies: ${missing_deps[*]}"
    log "ℹ️  Please install them using one of these methods:"
    log "   - Flatpak: Check if available via flatpak install"
    log "   - Homebrew: If you have Homebrew, try: brew install ${missing_deps[*]}"
    log "   - Toolbox: Use a toolbox container for installation"
    exit 1
  fi

  log "✅ All dependencies available"
}

install() {
  require_user

  log "🔤 Installing Nerd Fonts to $FONT_DIR..."

  # Create directories
  mkdir -p "$FONT_DIR" "$CACHE_DIR" || {
    log "❌ Failed to create directories"
    exit 1
  }
  
  mkdir -p "$TMP_DIR" || {
    log "❌ Failed to create temporary directory"
    exit 1
  }
  
  trap cleanup_temp EXIT

  local success_count=0
  local fail_count=0

  for name in "${!FONTS[@]}"; do
    # Check if font files already exist (more reliable than fc-list)
    local existing_files
    existing_files=$(find "$FONT_DIR" -type f -iname "*${name}*" 2>/dev/null | head -1 || true)
    if [[ -n "$existing_files" ]]; then
      log "✅ $name Nerd Font files already exist. Skipping."
      success_count=$((success_count + 1))
      continue
    fi

    zip_path="$TMP_DIR/${name}.zip"
    log "⬇️  Downloading $name Nerd Font..."
    
    local download_ok=false
    if command -v wget &>/dev/null 2>&1; then
      if wget -q -O "$zip_path" "${FONTS[$name]}" 2>/dev/null; then
        download_ok=true
      fi
    elif command -v curl &>/dev/null 2>&1; then
      if curl -fsSL -o "$zip_path" "${FONTS[$name]}" 2>/dev/null; then
        download_ok=true
      fi
    fi
    
    if [[ "$download_ok" != "true" ]]; then
      log "❌ Failed to download $name"
      fail_count=$((fail_count + 1))
      continue
    fi

    if [[ ! -f "$zip_path" || ! -s "$zip_path" ]]; then
      log "❌ Downloaded file is empty or missing for $name"
      fail_count=$((fail_count + 1))
      continue
    fi

    log "📦 Extracting $name..."
    if unzip -o -q "$zip_path" -d "$FONT_DIR" 2>/dev/null; then
      rm -f "$zip_path"
      
      # Verify files were extracted
      local extracted_files
      extracted_files=$(find "$FONT_DIR" -type f -iname "*${name}*" 2>/dev/null | head -1 || true)
      if [[ -n "$extracted_files" ]]; then
        log "✅ Installed $name Nerd Font"
        success_count=$((success_count + 1))
      else
        log "⚠️  $name extracted but no font files found"
        fail_count=$((fail_count + 1))
      fi
    else
      log "❌ Failed to extract $name"
      rm -f "$zip_path" || true
      fail_count=$((fail_count + 1))
    fi
  done

  if [[ $success_count -gt 0 ]]; then
    log "🔄 Rebuilding font cache..."
    if fc-cache -fv "$FONT_DIR" > "$FONT_CACHE_LOG" 2>&1; then
      log "✅ Font cache rebuilt"
    else
      log "⚠️  Font cache rebuild had warnings (checking if fonts are still usable)"
    fi
    log "✅ Nerd Fonts installation complete ($success_count succeeded, $fail_count failed)"
  else
    log "❌ No fonts were successfully installed"
    exit 1
  fi
}

config() {
  require_user

  log "🔧 Verifying Nerd Fonts installation..."

  local installed_count=0
  local file_count=0
  
  for name in "${!FONTS[@]}"; do
    # Check for font files first (most reliable)
    local font_files
    font_files=$(find "$FONT_DIR" -type f -iname "*${name}*" 2>/dev/null | wc -l || echo "0")
    
    if [[ $font_files -gt 0 ]]; then
      log "✅ $name Nerd Font files found ($font_files file(s))"
      file_count=$((file_count + 1))
      
      # Also check fc-list with multiple patterns
      local fc_found=false
      local fc_output
      fc_output=$(fc-list 2>/dev/null || true)
      for pattern in "$name Nerd Font" "$name" "Nerd Font.*$name"; do
        # Use subshell to avoid triggering ERR trap on grep failure
        if (set +e; echo "$fc_output" | grep -qi "$pattern" 2>/dev/null; [[ $? -eq 0 ]]); then
          fc_found=true
          break
        fi
      done
      
      if [[ "$fc_found" == "true" ]]; then
        log "   ✓ Available in font cache"
        installed_count=$((installed_count + 1))
      else
        log "   ⚠️  Not yet in font cache (may need app restart)"
        log "   ℹ️  Try running: fc-cache -fv $FONT_DIR"
      fi
    else
      log "⚠️  $name Nerd Font files not found"
    fi
  done

  if [[ $file_count -gt 0 ]]; then
    log "✅ $file_count font(s) installed ($installed_count in cache)"
    log "ℹ️  Fonts are available to applications that support them"
    log "ℹ️  You may need to restart applications to see the fonts"
    if [[ $installed_count -lt $file_count ]]; then
      log "ℹ️  Some fonts not in cache yet - this is normal after installation"
    fi
  else
    log "⚠️  No Nerd Font files found. Run 'install' first."
    exit 1
  fi

  log "✅ Nerd Fonts configuration complete"
}

clean() {
  require_user

  log "🧹 Removing installed Nerd Fonts..."

  local removed_count=0
  for name in "${!FONTS[@]}"; do
    # Find and remove font files matching the font name
    while IFS= read -r font_file || [[ -n "$font_file" ]]; do
      if [[ -n "$font_file" && -f "$font_file" ]]; then
        rm -f "$font_file" || true
        removed_count=$((removed_count + 1))
      fi
    done < <(find "$FONT_DIR" -type f -iname "*${name}*" 2>/dev/null || true)
  done

  if [[ $removed_count -gt 0 ]]; then
    log "🔄 Rebuilding font cache..."
    mkdir -p "$CACHE_DIR"
    fc-cache -fv "$FONT_DIR" > "$FONT_CACHE_LOG" 2>&1 || true
    log "✅ Removed $removed_count font file(s)"
  else
    log "ℹ️  No Nerd Fonts found to remove"
  fi

  log "✅ Clean complete"
}

case "$ACTION" in
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
all)
  deps
  install
  config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac
