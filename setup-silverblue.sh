#!/bin/bash
# Setup script for Fedora Silverblue
# Runs prerequisites first, then all install scripts if prerequisites are installed

set -Euo pipefail
trap 'echo "❌ setup-silverblue.sh failed at: $BASH_COMMAND (line $LINENO)" >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SILVERBLUE_DIR="$SCRIPT_DIR/modules/silverblue"
PREREQ_SCRIPT="$SILVERBLUE_DIR/packages/install-silverblue-prereq.sh"

# === OS Check ===
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* ]]; then
  echo "❌ This script is for Fedora Silverblue only."
  echo "   Detected OS: $ID"
  exit 1
fi

# === Check if prereq script exists ===
if [[ ! -f "$PREREQ_SCRIPT" ]]; then
  echo "❌ Prerequisite script not found: $PREREQ_SCRIPT"
  exit 1
fi

# Make sure prereq script is executable
chmod +x "$PREREQ_SCRIPT"

# === Step 1: Install Prerequisites ===
echo "📦 Step 1: Installing prerequisites via rpm-ostree..."
echo ""

"$PREREQ_SCRIPT" all

# === Step 2: Check if all packages are installed ===
echo ""
echo "🔍 Step 2: Verifying all prerequisite packages are installed..."

# Load packages from the packages file
PACKAGES_TXT="$SILVERBLUE_DIR/packages/rpm-ostree-packages.txt"
if [[ ! -f "$PACKAGES_TXT" ]]; then
  echo "❌ Packages file not found: $PACKAGES_TXT"
  exit 1
fi

# Read packages from file (skip comments and empty lines)
declare -a PACKAGES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue
  PACKAGES+=("$line")
done < "$PACKAGES_TXT"

# Check if all packages are installed
ALL_INSTALLED=true
MISSING_PACKAGES=()

for pkg in "${PACKAGES[@]}"; do
  if ! rpm -q "$pkg" &>/dev/null 2>&1; then
    ALL_INSTALLED=false
    MISSING_PACKAGES+=("$pkg")
  fi
done

if [[ "$ALL_INSTALLED" == "false" ]]; then
  echo ""
  echo "⚠️  Not all prerequisite packages are installed yet."
  echo "   Missing packages: ${MISSING_PACKAGES[*]}"
  echo ""
  echo "ℹ️  Please reboot your system to apply rpm-ostree changes, then run this script again:"
  echo "   sudo reboot"
  echo ""
  echo "   After reboot, run:"
  echo "   $0"
  exit 0
fi

echo "✅ All prerequisite packages are installed!"
echo ""

# === Step 3: Run all install scripts ===
echo "🚀 Step 3: Running all install scripts in modules/silverblue..."
echo ""

# Priority scripts (must run first, in this order)
PRIORITY_SCRIPTS=(
  "install-homebrew.sh"
)

# Find all install scripts, excluding not_used and packages directories
mapfile -t all_scripts < <(
  find "$SILVERBLUE_DIR" -maxdepth 1 -type f -name "install-*.sh" \
    -not -path "*/not_used/*" \
    -not -path "*/packages/*" \
    -print 2>/dev/null | sort
)

if (( ${#all_scripts[@]} == 0 )); then
  echo "ℹ️  No install scripts found in $SILVERBLUE_DIR"
  exit 0
fi

# Separate priority scripts from the rest
declare -a priority_scripts=()
declare -a remaining_scripts=()

for script in "${all_scripts[@]}"; do
  script_name="$(basename "$script")"
  is_priority=false
  
  for priority in "${PRIORITY_SCRIPTS[@]}"; do
    if [[ "$script_name" == "$priority" ]]; then
      priority_scripts+=("$script")
      is_priority=true
      break
    fi
  done
  
  if [[ "$is_priority" == "false" ]]; then
    remaining_scripts+=("$script")
  fi
done

echo "Found ${#all_scripts[@]} install script(s):"
for script in "${all_scripts[@]}"; do
  script_name="$(basename "$script")"
  for priority in "${PRIORITY_SCRIPTS[@]}"; do
    if [[ "$script_name" == "$priority" ]]; then
      echo "  - $script_name (priority)"
      break
    fi
  done || echo "  - $script_name"
done
echo ""

# Run priority scripts first
if (( ${#priority_scripts[@]} > 0 )); then
  echo "📌 Running priority scripts first..."
  for script in "${priority_scripts[@]}"; do
    script_name="$(basename "$script")"
    echo "▶️  Running (priority): $script_name"
    
    chmod +x "$script"
    
    if bash "$script" all; then
      echo "✅ Finished: $script_name"
    else
      echo "❌ Failed: $script_name"
      echo "   Continuing with remaining scripts..."
    fi
    echo ""
  done
fi

# Run remaining scripts
if (( ${#remaining_scripts[@]} > 0 )); then
  echo "📦 Running remaining scripts..."
  for script in "${remaining_scripts[@]}"; do
    script_name="$(basename "$script")"
    echo "▶️  Running: $script_name"
    
    chmod +x "$script"
    
    if bash "$script" all; then
      echo "✅ Finished: $script_name"
    else
      echo "❌ Failed: $script_name"
      echo "   Continuing with remaining scripts..."
    fi
    echo ""
  done
fi

echo "✅ Setup complete!"
echo ""
echo "ℹ️  Note: If you installed packages via rpm-ostree, a reboot may be required"
echo "   for some changes to take effect."
