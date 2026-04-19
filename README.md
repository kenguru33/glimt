<div align="center">

# ✨ Glimt — Fedora Post-Install Automation

**One command. Fully configured Fedora developer workstation.**

Automate your Fedora Workstation setup after a fresh install — shell, GNOME desktop, Kubernetes tools, and developer apps configured and ready in minutes.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platform: Fedora](https://img.shields.io/badge/platform-Fedora-294172)
![Shell: Bash](https://img.shields.io/badge/shell-bash-89e051)

<br>

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kenguru33/glimt/main/bootstrap.sh)
```

<br>

<img src="./screenshot.png" alt="Glimt running on Fedora Workstation — post-install automation" width="720">

</div>

---

## What is Glimt?

Glimt is a **Fedora post-install script** that automates setting up a developer workstation after a fresh Fedora installation. Instead of spending hours reinstalling packages, reconfiguring GNOME, and hunting down binaries every time you reinstall, a single command restores your entire environment.

It covers everything: ZSH with Starship prompt, GNOME desktop configuration, Kubernetes CLI tools, Neovim with LazyVim, Node.js version management, Btrfs snapshots, and optional extras like VS Code, Docker, JetBrains, and 1Password — all installed and configured automatically.

---

## 🤔 Why Glimt?

Reinstalling Fedora Workstation means hours of repetitive work — installing packages with `dnf`, tweaking GNOME settings, downloading binaries, wiring up dotfiles. Glimt automates the entire Fedora post-installation process in one run and gives you a CLI to manage it afterwards.

- 🔁 **Idempotent** — run it again any time, it picks up where it left off
- 🧩 **Modular** — every tool is its own script; install or clean individually
- 🎛️ **Pick what you want** — core modules run automatically, extras are opt-in via an interactive picker
- 🔓 **No root required** — run as your normal user, glimt uses sudo only when needed

---

## 📦 What you get

### 💻 Shell & terminal

A modern ZSH setup with Starship prompt, Catppuccin Mocha colors, Nerd Fonts, and all the CLI essentials.

| Module | | Module | |
|---|---|---|---|
| `zsh` | ZSH + config scaffolding | `bat` | `cat` with syntax highlighting |
| `starship` | Starship prompt | `eza` | Modern `ls` replacement |
| `fzf` | Fuzzy finder | `btop` | Resource monitor |
| `pbcopy` | Wayland `pbcopy`/`pbpaste` | | |

### 🛠️ Development tools

Git with GNOME Keyring, Neovim + LazyVim, Node.js version management, and GitHub CLI out of the box.

| Module | | Module | |
|---|---|---|---|
| `git-config` | Git + Keyring credentials | `lazyvim` | LazyVim config |
| `nvim` | Neovim | `volta` | Node.js version manager |
| `gh` | GitHub CLI + ZSH completion | | |

### ☸️ Kubernetes & cloud

Everything you need to work with clusters from day one.

| Module | | Module | |
|---|---|---|---|
| `kubectl` | kubectl | `helm` | Helm |
| `kubectx` | kubens / kubectx | `k9s` | k9s TUI |
| `azure-cli` | Azure CLI | | |

### 🎨 GNOME desktop

Tiling, blur effects, Catppuccin terminal, Papirus icons, and your Gravatar as your user avatar.

| Module | | Module | |
|---|---|---|---|
| `gnome-config` | Wallpaper, UI, keybindings | `nerdfonts` | Nerd Fonts |
| `gnome-extensions` | Tiling Shell, Blur My Shell, GSConnect, AppIndicator | `papirus-icon-theme` | Papirus icons |
| `gnome-terminal-theme` | Catppuccin Mocha terminal theme | `gravatar` | Gravatar user avatar |
| `just-perfection` | Fine-tune GNOME Shell UI | `gnome-caffeine` | Caffeine — prevent screen lock |

### ⚙️ System

| Module | | Module | |
|---|---|---|---|
| `flatpak` | Flatpak + Flathub | `btrfs-config` | Btrfs snapshots + snapper + dnf hooks |
| `chrome` | Google Chrome | `norwegian-mac-keyboard` | Norwegian Mac layout |

---

## 🎛️ Extras — pick what you need

Optional modules are selected through an interactive picker during setup. Add or remove them any time with `glimt module-selection`.

<details>
<summary>🚀 <strong>Applications</strong></summary>

| Module | Installs |
|---|---|
| `1password` | 1Password |
| `1password-cli` | 1Password CLI (`op`) |
| `discord` | Discord (Flatpak) |
| `spotify` | Spotify (Flatpak) |
| `gitkraken` | GitKraken |
| `tableplus` | TablePlus |
| `pika` | Pika Backup |

</details>

<details>
<summary>🌐 <strong>Web apps</strong></summary>

| Module | Installs |
|---|---|
| `notion` | Notion |
| `outlook` | Outlook |
| `teams` | Microsoft Teams |
| `chatgpt` | ChatGPT |
| `ytmusic` | YouTube Music |

</details>

<details>
<summary>🧰 <strong>Dev & infra</strong></summary>

| Module | Installs |
|---|---|
| `vscode` | Visual Studio Code |
| `jetbrains-toolbox` | JetBrains Toolbox |
| `dotnet` | .NET SDK 8 + 10 (userspace, no sudo) |
| `docker-rootless` | Docker rootless mode |
| `lazydocker` | LazyDocker TUI |
| `lens` | Lens Kubernetes desktop |
| `zellij` | Zellij terminal multiplexer |
| `claude-code` | Claude Code CLI (Anthropic AI assistant) |

</details>

---

## 🖥️ Glimt CLI

After setup, `glimt` is installed to `~/.local/bin/glimt` with full tab completion.

```bash
glimt install <module>      # 📥 install or reinstall a module
glimt clean <module>        # 🧹 remove a module cleanly
glimt module-selection      # 🎛️ interactive extras picker
glimt update                # 🔄 pull latest and re-run
```

---

## 📝 Notes

🔐 **Git credentials** — configured to use `git-credential-libsecret` (GNOME Keyring). Enable the socket if needed:

```bash
systemctl --user enable --now gnome-keyring-daemon.socket
```

---

## About

Glimt is a Fedora Workstation post-install automation tool written in Bash. It is designed for developers who reinstall Fedora regularly and want a reproducible, automated setup without Ansible or other heavy orchestration tools.

**Keywords:** Fedora post-install script, Fedora workstation setup, automate Fedora, Fedora developer environment, Fedora dotfiles, Fedora fresh install, GNOME setup script, Fedora bash script, Fedora workstation automation
