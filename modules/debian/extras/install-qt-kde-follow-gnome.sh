#!/usr/bin/env bash
# qt-kde-follow-gnome.sh — Debian Trixie (GNOME):
# Make Qt apps follow GNOME + make KDE apps (e.g., gconnect) match GNOME light/dark.
# Actions: all | deps | install | config | sync-now | clean
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

ACTION="${1:-all}"

# ===== Helpers =====
info() { echo "➜ $*"; }
ok()   { echo "✅ $*"; }
warn() { echo "⚠️  $*" >&2; }

# ===== Debian-only guard =====
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "$ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
    echo "❌ This script is for Debian. Detected: $PRETTY_NAME"
    exit 1
  fi
else
  echo "❌ Cannot detect OS."
  exit 1
fi

# ===== Paths =====
ENV_DIR="$HOME/.config/environment.d"
ENV_FILE="$ENV_DIR/90-qt-gnome.conf"

BIN_DIR="$HOME/.local/bin"
SYNC_BIN="$BIN_DIR/gnome-kde-theme-sync"

AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/gnome-kde-theme-sync.desktop"

KDE_GLOBALS="$HOME/.config/kdeglobals"

# ----- Install required packages -----
install_deps() {
  info "Updating apt and installing Qt↔GTK bridge + minimal KDE bits…"
  sudo apt update
  sudo apt install -y \
    qt5-gtk-platformtheme \
    qt6-gtk-platformtheme \
    adwaita-qt \
    breeze \
    breeze-icon-theme
  ok "Packages installed."
}

# ----- Configure Qt to follow GNOME -----
configure_qt_env() {
  info "Configuring per-user environment for Qt to follow GNOME…"
  mkdir -p "$ENV_DIR"
  cat > "$ENV_FILE" <<'EOF'
# Make Qt apps follow GNOME/GTK theme (Adwaita, light/dark)
QT_QPA_PLATFORMTHEME=gtk3

# Safety: avoid overrides that break following GNOME
# (Uncomment the next line if you ever set this in your shell)
# QT_STYLE_OVERRIDE=
EOF
  ok "Wrote $ENV_FILE"
}

# ----- Create sync script for KDE apps (Kirigami/KColorScheme users) -----
create_sync_script() {
  info "Writing sync helper to keep KDE apps in step with GNOME…"
  mkdir -p "$BIN_DIR"
  cat > "$SYNC_BIN" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Read GNOME color preference
SCHEME="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || echo \"'default'\" )"
SCHEME="${SCHEME//\'}"  # strip single quotes

# Decide KDE scheme name
# Breeze (light) or BreezeDark (dark)
if [[ "$SCHEME" == *prefer-dark* ]]; then
  KDE_SCHEME="BreezeDark"
else
  KDE_SCHEME="Breeze"
fi

KDE_GLOBALS="$HOME/.config/kdeglobals"
mkdir -p "$(dirname "$KDE_GLOBALS")"

# Write/patch kdeglobals minimally
if [[ -f "$KDE_GLOBALS" ]]; then
  # Replace or add ColorScheme under [General]
  if grep -q '^\[General\]' "$KDE_GLOBALS"; then
    awk -v scheme="$KDE_SCHEME" '
      BEGIN{in_gen=0}
      /^\[General\]/{print; in_gen=1; next}
      /^\[/ && $0 !~ /^\[General\]/{ if(in_gen && !printed){print "ColorScheme=" scheme; printed=1} in_gen=0; print; next}
      {
        if(in_gen && $0 ~ /^ColorScheme=/){print "ColorScheme=" scheme; seen=1}
        else {print}
      }
      END{
        if(in_gen && !seen){print "ColorScheme=" scheme}
      }
    ' "$KDE_GLOBALS" > "$KDE_GLOBALS.tmp" && mv "$KDE_GLOBALS.tmp" "$KDE_GLOBALS"
  else
    {
      echo "[General]"
      echo "ColorScheme=$KDE_SCHEME"
      echo
      cat "$KDE_GLOBALS"
    } > "$KDE_GLOBALS.tmp" && mv "$KDE_GLOBALS.tmp" "$KDE_GLOBALS"
  fi
else
  cat > "$KDE_GLOBALS" <<EOF_INNER
[General]
ColorScheme=$KDE_SCHEME
EOF_INNER
fi

# Hint: also sync icons to Breeze (harmless if absent)
if ! grep -q '^\[Icons\]' "$KDE_GLOBALS" 2>/dev/null; then
  {
    echo
    echo "[Icons]"
    echo "Theme=breeze"
  } >> "$KDE_GLOBALS"
else
  awk '
    BEGIN{in_icons=0}
    /^\[Icons\]/{print; in_icons=1; next}
    /^\[/ && $0 !~ /^\[Icons\]/{ if(in_icons && !printed){print "Theme=breeze"; printed=1} in_icons=0; print; next}
    {
      if(in_icons && $0 ~ /^Theme=/){print "Theme=breeze"; seen=1}
      else {print}
    }
    END{
      if(in_icons && !seen){print "Theme=breeze"}
    }
  ' "$KDE_GLOBALS" > "$KDE_GLOBALS.tmp" && mv "$KDE_GLOBALS.tmp" "$KDE_GLOBALS"
fi

exit 0
EOF
  chmod +x "$SYNC_BIN"
  ok "Wrote $SYNC_BIN"
}

# ----- Autostart the sync on login -----
create_autostart() {
  info "Creating Autostart entry so KDE apps follow GNOME on every login…"
  mkdir -p "$AUTOSTART_DIR"
  cat > "$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=GNOME→KDE Theme Sync
Exec=$SYNC_BIN
X-GNOME-Autostart-enabled=true
OnlyShowIn=GNOME;Unity;
EOF
  ok "Wrote $AUTOSTART_FILE"
}

# ----- One-shot sync now -----
sync_now() {
  if [[ ! -x "$SYNC_BIN" ]]; then
    warn "Sync script missing; creating it first…"
    create_sync_script
  fi
  "$SYNC_BIN"
  ok "Synced KDE scheme to match current GNOME color-scheme."
}

# ----- Clean up everything this script created (keeps packages) -----
do_clean() {
  [[ -f "$ENV_FILE" ]] && { info "Removing $ENV_FILE"; rm -f "$ENV_FILE"; ok "Removed."; } || warn "No $ENV_FILE"
  [[ -f "$SYNC_BIN" ]] && { info "Removing $SYNC_BIN"; rm -f "$SYNC_BIN"; ok "Removed."; } || warn "No $SYNC_BIN"
  [[ -f "$AUTOSTART_FILE" ]] && { info "Removing $AUTOSTART_FILE"; rm -f "$AUTOSTART_FILE"; ok "Removed."; } || warn "No $AUTOSTART_FILE"

  warn "Installed packages were not removed. To purge:"
  echo "    sudo apt purge qt5-gtk-platformtheme qt6-gtk-platformtheme adwaita-qt breeze breeze-icon-theme"
}

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    configure_qt_env
    create_sync_script
    create_autostart
    ;;
  config)
    configure_qt_env
    create_sync_script
    create_autostart
    ;;
  sync-now)
    sync_now
    ;;
  clean)
    do_clean
    ;;
  all)
    install_deps
    configure_qt_env
    create_sync_script
    create_autostart
    sync_now
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|sync-now|clean]"
    exit 1
    ;;
esac

cat <<'NOTE'

Verification:
  • Ensure GNOME dark mode if desired:
      gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  • Launch a KDE app (e.g., gconnect). It should match GNOME (BreezeDark in dark mode, Breeze in light).
  • Toggle GNOME light/dark, then run:
      qt-kde-follow-gnome.sh sync-now
    (It will also auto-run at next login.)

Notes:
  • Flatpak KDE apps may ignore host configs. Prefer Debian packages or ensure matching theme runtimes.
  • If any app still forces its own style, check it isn’t launched with QT_STYLE_OVERRIDE or custom flags.

NOTE
