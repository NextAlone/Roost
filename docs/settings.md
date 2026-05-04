# Settings

Open settings with `Cmd+,` (**Roost → Settings...**).

## General

- **Auto‑expand worktrees on project switch** — automatically opens the worktree list when you switch to a project that has more than one.
- **Keep projects open after closing all tabs** — keeps a project visible in the sidebar even after its last tab is closed.
- **Confirm before closing tab with running process** — prompts before killing a non‑idle terminal.
- **Confirm before quitting Roost** — confirmation dialog on `Cmd+Q`. Includes a "Don't ask again" toggle.

## Appearance

- **Theme** — paired light / dark theme picker.
- **Syntax highlighting theme** — applied to the built‑in editor.

See [Themes](features/themes.md).

## Editor

- **Default editor** — built-in Roost editor, or an external command.
- **External editor command** — used when default is set to "external". `{file}`, `{line}`, `{column}` placeholders are substituted.
- **Wrap lines** — opt-in soft wrapping in the built-in editor. It is off by default to preserve the fast unwrapped path.
- **Font** — font family and size for the built‑in editor.

## Keyboard Shortcuts

- All actions remappable via a key‑capture recorder.
- **Custom Commands** — define reusable shell command shortcuts.

See [Keyboard Shortcuts](keyboard-shortcuts.md).

## Notifications

- **Enable notifications** — global toggle.
- **Toast position** — top or bottom of the window.
- **Sound** — play a system sound on arrival.
- **Per‑source delivery** — separate toggles for Claude Code, OpenCode, OSC sequences, and the socket API.

See [Notifications](features/notifications.md).

## Mobile

- **Enable Mobile Server** — start / stop the WebSocket server.
- **Port** — defaults to 4865.
- **Approved devices** — list of paired clients with revoke buttons.

See [Remote Server](features/remote-server.md).

## AI Usage

- **Enable AI usage tracking** — global toggle.
- **Display mode** — show *used* or *remaining* values.
- **Auto‑refresh** — Off / 5m / 15m / 30m / 1h.
- **Show secondary limits** — keep / hide non‑primary metrics.
- **Per‑provider toggles** — enable each provider individually.

See [AI Usage](features/ai-usage.md).
