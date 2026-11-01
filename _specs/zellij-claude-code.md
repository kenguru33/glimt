# Zellij Tuned for Claude Code

## Summary

Adapt Glimt's zellij setup (macOS and Fedora extras) for working with Claude Code. Every zellij session, tab and pane should make it obvious which project you are in. Zellij's default keys should stop stealing Claude Code's shortcuts. The feature is for Glimt users who run one or more Claude Code sessions inside zellij.

## Problem

- **You can't see which project you are in.** The auto-start runs a bare `zellij`, so each session gets a random name (e.g. `dazzling-tiger`). Tabs are named `Tab #1`, `Tab #2`, and the compact layout hides pane frames, so the pane title Claude Code sets (status + topic) is never shown. With several Claude sessions open, they look identical.
- **The kitty tab names stop helping.** kitty now names tabs after the project and Claude's title, but inside zellij the foreground process is zellij, not Claude. The kitty tab then shows only what zellij reports.
- **Zellij's keys collide with Claude Code's.** Zellij's default "normal" mode grabs `Ctrl+T`, `Ctrl+O`, `Ctrl+G`, `Ctrl+S`, `Ctrl+B`, `Ctrl+P` and others. Claude Code uses several of these (todo list, verbose output, open in editor, background tasks, history), so they never reach Claude.
- **The two platforms have drifted apart.** macOS writes its config inline from the install script instead of using `deploy_config`, so there is no backup. Fedora deploys a template but lacks `osc8_hyperlinks`, so clickable file links from Claude don't work there.

## Goals

- The current project is visible at a glance in the zellij session name, the tab names and the status bar.
- The project shows up in kitty's tab bar too when zellij runs inside kitty.
- Claude Code's own keyboard shortcuts work inside zellij without extra steps.
- Claude Code's status (working / idle / waiting for input) is visible for every pane that runs it, including panes without focus.
- macOS and Fedora get the same zellij behavior from a shared, deployed config template.

## Non-goals

- Replacing zellij with tmux or kitty-native multiplexing.
- Changing how Claude Code itself is installed or configured, beyond what's needed for it to run well in zellij.
- Custom-built zellij plugins. Use built-in features or one established, pinned community plugin at most.
- Changing zellij from an optional extra into a core module.
- Making zellij auto-start on by default for users who don't want it.

## User stories

- As a developer with three Claude Code sessions in different repos, I want each zellij session and tab named after its project, so I can tell them apart without switching to them.
- As a developer using Claude Code inside zellij, I want `Ctrl+T`, `Ctrl+O` and `Ctrl+G` to reach Claude, so I can use its todo list, transcript and editor features.
- As a developer, I want to see in the tab or status bar when Claude has finished or is waiting for me, so I can switch to it at the right moment.
- As a developer who reopens a terminal in a project, I want to land back in that project's existing zellij session instead of a new random one.
- As a Glimt user on Fedora, I want the same zellij experience as on macOS.

## Requirements

### Functional

- New zellij sessions started by the shell auto-start are named after the project: the git repository's name, or the folder name outside a repo.
- If a session for that project already exists, the auto-start attaches to it instead of creating a new one.
- Tab names follow the project the tab works in and update when the working directory moves to another repository.
- The status bar shows the session or project name, the tab list and the active zellij mode.
- Every pane running Claude Code shows the pane title Claude sets, i.e. its status symbol and topic, without the user turning pane frames on by hand.
- Zellij uses a keybinding preset that doesn't intercept Claude Code's shortcuts (for example zellij's "unlock-first" preset, or a locked-by-default mode). The way to reach zellij's own actions is documented.
- The terminal title zellij sends to the host terminal includes the project name, so kitty's tab names keep showing the project.
- Clickable file links (OSC 8) are passed through to the host terminal on both macOS and Fedora.
- Bells and notifications from Claude Code (finished / needs input) reach the host terminal, so kitty can mark the tab and macOS/GNOME can notify.
- The zellij config is deployed from a template in the repo with `deploy_config` on both platforms; macOS stops writing it inline.
- `glimt clean zellij` removes everything the feature adds (config, layouts, shell hooks, plugins) and leaves the user's sessions alone.
- [docs/SHORTCUTS.md](../docs/SHORTCUTS.md) gets a zellij section with the keybinding preset and how to reach zellij's actions.

### Non-functional

- **Speed:** Shell start-up stays fast. Project detection must not run `git` subprocesses on every prompt; a cheap directory walk or a hook on directory change is acceptable.
- **Pinned versions:** A community plugin, if one is used, must be pinned in `versions.env` and downloaded for the right architecture, like other pinned binaries.
- **Safe re-runs:** Running `glimt update` / `glimt install zellij` is idempotent and doesn't re-download anything already current.
- **Conventions:** Follows Glimt's module conventions (`set -Eeuo pipefail`, `deploy_config`, `run_as_user`, `fedora_guard`/`macos_guard`, `confirm` for prompts).
- **Theme:** Catppuccin Mocha stays the theme.
- **Tests:** The existing test suite passes, with new tests for the deployed files and the session-naming logic.

## User experience

- **Opening a terminal in a repo:** you land in a zellij session named after it (e.g. `glimt`). The status bar shows `glimt`, and the kitty tab shows `glimt` too.
- **Reopening the same project:** a new terminal in the same project attaches to the running session instead of creating a new one.
- **Moving to another repo:** after `cd` into another repo, the current tab is renamed after it.
- **Claude panes:** a pane running Claude shows Claude's title in the pane frame or status area, e.g. `✳ Fix login bug` when idle and a spinner while it works.
- **Background panes:** a pane where Claude rang the bell is marked in the tab bar until you visit it.
- **Keys:** Claude's shortcuts work directly. Zellij's actions sit behind one unlock key, which is shown in the status bar and in `docs/SHORTCUTS.md`.
- **Outside a project:** in the home folder or outside a repo, the session falls back to the folder name (`~` for home), with no error.

## Edge cases

- **Two terminals, same project:** both attach to the same session; this is zellij's normal multi-client behavior.
- **Same repo name, different paths** (e.g. two clones called `api`): sessions must not merge by accident. Disambiguate the name (e.g. with the parent folder) or ask.
- **Invalid session names:** zellij rejects some characters, and repo names may start with a dot (e.g. `.glimt`). Names are sanitized so session creation never fails.
- **Exited session with the same name:** the auto-start resurrects it or replaces it cleanly instead of failing.
- **SSH, VS Code terminal, tmux, non-interactive shells:** the auto-start stays off, as today.
- **kitty splits and kitty sessions:** each kitty split today starts its own zellij via auto-start. Opening a kitty session that runs `claude -r` must not nest zellij or start duplicate sessions for the same project.
- **Claude in a subfolder:** a Claude Code session started in a subfolder of a repo is named after the repo, not the subfolder.
- **No git:** project detection falls back to the folder name.
- **Downloaded plugin missing:** if a downloaded plugin is missing or fails to load, zellij still starts with the built-in status bar.

## Acceptance criteria

- [ ] Opening a new terminal in `~/.glimt` gives a zellij session named after the project (e.g. `glimt`), and the kitty tab shows the project name.
- [ ] Opening a second terminal in the same project attaches to the existing session instead of creating a new one.
- [ ] Tab names show the project and update after `cd` into another repository.
- [ ] A pane running Claude Code shows Claude's title, with status symbol and topic, without manual setup.
- [ ] `Ctrl+T`, `Ctrl+O` and `Ctrl+G` reach Claude Code inside zellij.
- [ ] A bell from Claude Code in a pane without focus marks the zellij tab and the kitty tab.
- [ ] Shift+click on a file link from Claude opens it, on both macOS and Fedora.
- [ ] macOS and Fedora deploy the same zellij config template via `deploy_config`, with a backup of any existing config.
- [ ] `glimt clean zellij` removes the config, layouts, hooks and plugins.
- [ ] `docs/SHORTCUTS.md` has a zellij section.
- [ ] `bash tests/run.sh` passes, including new tests for the zellij module.

## Dependencies and assumptions

- Zellij tracks the latest release (not pinned), so keybinding presets and pane-title features from recent releases are available.
- Claude Code sets the terminal/pane title via OSC escape codes and uses the terminal bell or OSC notifications to signal "done" / "waiting".
- The kitty tab naming from `modules/macos/config/kitty-tab-bar.py` stays as it is. This feature makes zellij report the project so kitty can show it.
- The zellij extra is installed and selected on the machine. Users without it see no change.
- If a status-bar plugin such as zjstatus is used, it will be pinned in `versions.env`.

## Decisions

- **Status bar:** the built-in compact bar, plus pane title frames (`pane_frame_style "titles"`). No plugin.
- **Keybindings:** zellij's Unlock-First preset with `Ctrl+G` to unlock. It is copied into the template from zellij v0.45.1, because no released zellij can pick a preset by name yet. `Alt+P` (pane groups) is left out because it is Claude Code's model picker.
- **Second terminal in a project:** a live session is never shared. You get `name-2`, `name-3`, …, and an exited session is resurrected.
- **Auto-start:** stays on, with `GLIMT_ZELLIJ_AUTOSTART=0` as the opt-out.
- **Notifications:** zellij 0.44.1+ forwards OSC 99, and 0.45.0+ forwards OSC 9/777 and focus events, so no workaround is needed.
- **Known limitation (duplicate repo names):** sessions are named only after the repo, so two clones called `api` share the name prefix. An exited `api` session may be resurrected from the other clone's folder.
