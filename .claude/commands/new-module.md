# Create a new Glimt install module

Create a new Glimt module script for the tool named **$ARGUMENTS**.

Parse the arguments:
- First word is the **module name** (e.g. `ripgrep` or `ripgrep --optional`)
- If `--optional` flag is present, place the module in `modules/fedora/extras/`; otherwise place it in `modules/fedora/`

## Steps

1. Ask the user (via text, not a tool) these questions if the answers aren't already clear from the argument:
   - What is the module name?
   - Is this a core module or an optional/extras module? (core = `modules/fedora/`, extras = `modules/fedora/extras/`)
   - How is the tool installed? Choose one:
     a. DNF package (provide the dnf package name)
     b. Flatpak (provide the Flatpak app ID, e.g. `org.example.App`)
     c. Binary download from GitHub releases (provide the GitHub repo, e.g. `owner/repo`)
     d. Custom / other

2. Generate the module script at the correct path:
   - Core:   `modules/fedora/install-<name>.sh`
   - Extras: `modules/fedora/extras/install-<name>.sh`

3. Follow these rules from CLAUDE.md exactly:
   - `set -Eeuo pipefail` + ERR trap at the top
   - `MODULE_NAME`, `ACTION="${1:-all}"` variables
   - Source `lib.sh` with the correct relative path:
     - Core:   `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"`
     - Extras: `"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"`
   - Implement exactly: `deps()`, `install()`, `config()`, `clean()` functions
   - `case "$ACTION"` dispatcher at the bottom: `all | deps | install | config | clean`
   - Use `run_as_user` / `sudo -u "$REAL_USER"` for user-home file ops — never write to `$HOME` directly
   - Use `deploy_config` (not bare `cp`) when deploying config templates
   - Call `verify_binary <bin> --version` after installing a binary
   - Never call `sudo dnf makecache -y` inside a module
   - Add `fedora_guard` for extras modules (copy the pattern from `modules/fedora/extras/install-spotify.sh`)

4. Use the right install template per install method:

   **DNF package:**
   ```bash
   deps()    { log "Installing <name>…"; sudo dnf install -y <pkg>; }
   install() { log "<name> installed via DNF."; verify_binary <bin> --version; }
   config()  { log "No config needed."; }
   clean()   { sudo dnf remove -y <pkg>; }
   ```

   **Flatpak:**
   ```bash
   deps()    { sudo dnf install -y flatpak; }
   install() {
     sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
     flatpak install -y flathub <APP_ID>
   }
   config()  { log "No config needed."; }
   clean()   {
     flatpak uninstall -y <APP_ID> || true
     flatpak uninstall -y --unused || true
   }
   ```

   **Binary from GitHub releases:**
   ```bash
   # Source versions.env if the version is pinned there
   install() {
     local url="https://github.com/<owner>/<repo>/releases/download/..."
     local tmp; tmp="$(mktemp)"
     curl -fsSL "$url" -o "$tmp"
     # extract / install to "$HOME_DIR/.local/bin/<name>"
     run_as_user install -Dm755 "$tmp" "$HOME_DIR/.local/bin/<name>"
     rm -f "$tmp"
     verify_binary <name> --version
   }
   ```

5. After writing the file, make it executable:
   ```bash
   chmod +x <path>
   ```

6. Run `shellcheck <path>` and fix any warnings before reporting done.

7. Report what was created, the install method used, and remind the user to test with:
   ```bash
   bash <path> all
   ```
