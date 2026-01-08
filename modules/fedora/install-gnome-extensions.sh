#!/usr/bin/env bash
set -euo pipefail

# Must be run from GNOME session
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  echo "ERROR: Run from GNOME Terminal (not sudo / tty / ssh)"
  exit 1
fi

EXTENSIONS=(
  blur-my-shell@aunetx
  tilingshell@ferrarodomenico.com
  appindicatorsupport@rgcjonas.gmail.com
  gsconnect@andyholmes.github.io
)

GNOME_MAJOR="$(gnome-shell --version | awk '{print int($3)}')"
TMP_ZIP="$(mktemp)"

install_one() {
  local uuid="$1"
  local search="$uuid"

  [[ "$uuid" == "tilingshell@ferrarodomenico.com" ]] && search="tiling-shell"

  local meta pk info dl

  meta="$(curl -fsSL \
    "https://extensions.gnome.org/extension-query/?search=${search}" |
    jq -r --arg u "$uuid" '.extensions[] | select(.uuid==$u)')"

  [[ -n "$meta" ]] || {
    echo "NOT FOUND: $uuid"
    return
  }

  pk="$(jq -r '.pk' <<<"$meta")"

  info="$(curl -fsSL \
    "https://extensions.gnome.org/extension-info/?pk=${pk}&shell_version=${GNOME_MAJOR}")"

  dl="$(jq -r '.download_url' <<<"$info")"
  [[ "$dl" != "null" ]] || {
    echo "NO COMPATIBLE VERSION: $uuid"
    return
  }

  curl -fsSL "https://extensions.gnome.org${dl}" -o "$TMP_ZIP"

  # 1) Install
  gnome-extensions install --force "$TMP_ZIP"
}

# --------------------------------------------------
# Install all
# --------------------------------------------------
for e in "${EXTENSIONS[@]}"; do
  install_one "$e"
done

# Cleanup
rm -f "$TMP_ZIP"
echo "DONE"

# -------------------------------
# Setup post-login enable (run once)
# -------------------------------

BIN="$HOME/.local/bin/enable-gnome-extensions-once.sh"
SERVICE="$HOME/.config/systemd/user/enable-gnome-extensions-once.service"

mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.config/systemd/user"

cat > "$BIN" <<'EOF'
#!/usr/bin/env bash
set -e

EXTENSIONS=(
  blur-my-shell@aunetx
  tilingshell@ferrarodomenico.com
  appindicatorsupport@rgcjonas.gmail.com
  gsconnect@andyholmes.github.io
)

for e in "${EXTENSIONS[@]}"; do
  gnome-extensions enable "$e" 2>/dev/null || true
done

# run once: disable and remove itself
systemctl --user disable enable-gnome-extensions-once.service || true
rm -f "$HOME/.config/systemd/user/enable-gnome-extensions-once.service"
rm -f "$HOME/.local/bin/enable-gnome-extensions-once.sh"
EOF

chmod +x "$BIN"

cat > "$SERVICE" <<EOF
[Unit]
Description=Enable GNOME extensions after first login
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/enable-gnome-extensions-once.sh

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload
systemctl --user enable enable-gnome-extensions-once.service

echo "Post-login extension enable installed. Log out and log back in."
