# ⌨️ Keyboard shortcuts

The shortcuts Glimt sets up on top of each application's defaults. Anything not listed here works as the application ships it.

---

## 🐱 kitty (macOS)

Configured in `~/.config/kitty/kitty.conf` (from `modules/macos/config/kitty.conf`).

### Splits

| Shortcut | Action |
|---|---|
| `⌘ D` | Vertical split — new window **to the right** (side by side) |
| `⌘ ⇧ D` | Horizontal split — new window **below** (stacked) |
| `⌘ ⌥ ←` `→` `↑` `↓` | Move focus to the split in that direction |

New splits open in the same folder as the window you split from.

### Sessions

A session is a saved set of tabs, splits, folders and running programs (for example Claude Code, btop and a shell side by side).

| Shortcut | Action |
|---|---|
| `⌃ ⇧ S` | **Save** the current session. Prompts for a name, pre-filled with the folder name |
| `⌃ ⇧ O` | **Open** a saved session (fzf picker; `Enter` opens, `Esc` cancels) |
| `⌃ ⇧ X` | **Close** the current session |
| `⌃ ⇧ ⌫` | **Delete** a saved session (fzf picker) |

Saved sessions live in `~/.local/share/kitty/sessions/`.

**Starting kitty with a session:** running `kitty` with no arguments from the shell opens

1. `.kitty.session` in the current folder, if there is one (a per-project layout), else
2. the default session `~/.config/kitty/default.session`.

Launching kitty from the Dock or Spotlight always opens the default session.

### Tab names

Tabs are named automatically as `[session] project · title`:

- **project** is the git repository the tab works in (or the folder name outside a repo).
- If a split in the tab runs **Claude Code**, the tab shows Claude's status and topic — `✳` when it is idle, a spinner while it works — even when another split has focus.
- 🔔 marks a tab in the background that rang the bell, e.g. Claude finishing or waiting for you.

---

## 🪟 zellij (optional extra, macOS and Fedora)

Configured in `~/.config/zellij/config.kdl` (from `modules/<os>/config/zellij.kdl`).

zellij starts **locked**: every `Ctrl` key goes to the program in the pane, so Claude Code's own shortcuts (`Ctrl+T`, `Ctrl+O`, `Ctrl+B`, …) work. Unlock zellij first, then press one letter:

| Shortcut | Action |
|---|---|
| `⌃ G` | **Unlock** zellij (press again, `Esc` or `Enter` to lock) |
| `⌃ G` `p` | Pane mode — `n` new, `r` right, `d` down, `x` close, `f` fullscreen, `w` floating, `c` rename |
| `⌃ G` `t` | Tab mode — `n` new, `r` rename, `x` close, `1`–`9` go to tab, `←` `→` previous/next |
| `⌃ G` `r` | Resize mode — `←` `↓` `↑` `→` or `h` `j` `k` `l` |
| `⌃ G` `m` | Move the pane — arrows or `h` `j` `k` `l` |
| `⌃ G` `s` | Scroll mode — `f` search, `e` open scrollback in your editor |
| `⌃ G` `o` | Session mode — `d` detach, `w` session manager, `c` settings |
| `⌃ G` `⌃ Q` | Quit zellij |

These also work while locked:

| Shortcut | Action |
|---|---|
| `⌥ N` | New pane |
| `⌥ ←` `→` `↑` `↓` (or `⌥ H` `J` `K` `L`) | Move focus between panes and tabs |
| `⌥ F` | Show/hide floating panes |
| `⌥ =` / `⌥ -` | Resize the pane |

`⌃ G` is also Claude Code's "open in editor" key, so inside zellij that key unlocks zellij instead. To get the editor back, give it another key with `/keybindings` in Claude Code.

**Sessions are named after the project.** A new terminal opens a session named after the git repository you are in (`.glimt` → `glimt`), or the folder name outside a repo. If that session is already open in another terminal, you get `glimt-2`, `glimt-3`, …; an exited session is brought back instead. Tabs are renamed after the project when you `cd` into another repo. Every pane shows its title in a title row, so a pane running Claude Code shows `✳` (idle) or a spinner (working) and the topic.

To stop zellij from starting automatically, add `export GLIMT_ZELLIJ_AUTOSTART=0` to `~/.zshenv`.

---

## 🐚 Shell (zsh, macOS and Fedora)

| Shortcut | Action |
|---|---|
| `Tab` | Completion in an fzf picker with a preview of files and folders (fzf-tab). Type to filter, `Enter` to pick |
| `→` | Accept the grey suggestion from your history (zsh-autosuggestions) |

---

## 🇳🇴 Norwegian Mac keyboard (Fedora)

Applies when the **Norwegian (Macintosh)** layout is selected in GNOME. The left Option key works like on macOS:

| Shortcut | Character |
|---|---|
| `⌥ 7` | `\|` |
| `⌥ ⇧ 7` | `\` |

Log out and back in after installing for this to take effect.
