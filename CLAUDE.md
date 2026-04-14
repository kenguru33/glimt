# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

Glimt is a **Fedora-only** post-installation automation tool. It installs and configures a development environment (shell, GNOME, Kubernetes tooling, etc.) on a fresh Fedora install. There is no build step, no test suite, and no package manager — everything is bash.

## Running things

```bash
# Run a single module end-to-end (on Fedora)
bash modules/fedora/install-<name>.sh all

# Run only a specific phase of a module
bash modules/fedora/install-<name>.sh deps
bash modules/fedora/install-<name>.sh install
bash modules/fedora/install-<name>.sh config
bash modules/fedora/install-<name>.sh clean

# Run an extras module the same way
bash modules/fedora/extras/install-<name>.sh all

# Run the full setup (as normal user with sudo)
bash setup.sh

# Post-install CLI (after glimt is installed to ~/.local/bin)
glimt install <module>
glimt clean <module>
glimt update
glimt module-selection
```

Static analysis (no CI enforces this, but useful):
```bash
shellcheck modules/fedora/lib.sh
shellcheck modules/fedora/install-<name>.sh
```

## Architecture

### Module system

Every installer lives in `modules/fedora/` (core) or `modules/fedora/extras/` (optional). Each module is a standalone script that implements exactly these actions via a `case` dispatcher at the bottom:

| Action | What it does |
|--------|-------------|
| `all` | deps + install + config (full setup) |
| `deps` | Install system packages via dnf |
| `install` | Install the tool (binary download, git clone, etc.) |
| `config` | Copy config templates, apply settings |
| `clean` | Remove everything the module installed |

### Shared library — `modules/fedora/lib.sh`

**All modules source this.** It provides the foundational primitives every module needs:

```bash
# Core modules:
GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
source "$GLIMT_LIB"

# Extras modules (one level deeper):
GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
source "$GLIMT_LIB"
```

After sourcing, available globals and functions:
- `REAL_USER` / `HOME_DIR` — resolves the invoking user via `getent` (safe under sudo, never `/root`)
- `log()`, `warn()`, `die()` — structured logging
- `run_as_user <cmd>` — runs a command as `$REAL_USER`
- `deploy_config <src> <dest>` — copies a template to dest, **automatically backs up** any existing file with a timestamp before overwriting
- `verify_binary <bin> [args]` — warns (does not abort) if a binary isn't functional after install

### Pinned versions — `versions.env`

Modules that download versioned binaries source this file for their version strings:

```bash
VERSIONS_ENV="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../versions.env"
source "$VERSIONS_ENV"
# Provides: $HELM_VERSION, $NERDFONTS_VERSION, $K9S_VERSION, $GUM_VERSION
```

Extras use `../../../versions.env`.

### Setup orchestration

`setup.sh` is the main orchestrator. Key details:
- Calls `dnf makecache -y` **once** before any modules run — individual modules must not call it
- Runs three **priority modules first** (in order): `install-gnome-config.sh`, `install-nerdfonts.sh`, `install-gnome-terminal-theme.sh`
- Then runs all remaining core modules via `find`, sorted alphabetically
- Calls `setup-extras.sh` at the end for optional modules

`setup-extras.sh` presents a `gum choose` UI and tracks selections in `~/.config/glimt/optional-extras.selected`. On re-run it installs newly selected modules and cleans deselected ones.

### Shell scripting conventions

Every module header must follow this pattern:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="my-module"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
source "$GLIMT_LIB"
```

Rules enforced across the codebase:
- `set -Eeuo pipefail` on every script — no exceptions
- `deploy_config` instead of bare `cp` for any config template deployment
- `sudo dnf makecache -y` only in `setup.sh`, never in modules
- Use `run_as_user` / `sudo -u "$REAL_USER"` for any file operations in user home — never write to `$HOME` directly when running under sudo
- Post-install: call `verify_binary` for any binary the module downloads

### Config templates

Templates live in `modules/fedora/config/` and are deployed to `~/.zsh/config/<name>.zsh` or `~/.zshrc`. The user's `~/.zshrc` sources everything in `~/.zsh/config/*.zsh` automatically.

### Bootstrap flow

```
bootstrap.sh          # curl/wget entry point; clones repo to ~/.glimt
  └─ setup.sh         # orchestrator; runs modules in order
       ├─ priority modules (gnome-config, nerdfonts, gnome-terminal-theme)
       ├─ remaining core modules (alphabetical)
       └─ setup-extras.sh  # optional extras via gum UI
```

After setup, `glimt.sh` is installed to `~/.local/bin/glimt` for ongoing management.
