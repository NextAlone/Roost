# Troubleshooting

If something goes wrong, this page collects the common fixes. If your issue isn't here, please [open an issue](https://github.com/NextAlone/Roost/issues).

## Logs

Roost writes logs through the unified macOS logging system. Stream them live:

```bash
log stream --predicate 'subsystem == "app.muxy"' --info --debug
```

Or grab a recent slice:

```bash
log show --predicate 'subsystem == "app.muxy"' --last 10m --info --debug
```

## Terminal is blank or unresponsive

- Try **Roost → Reload Configuration** (`Cmd+Shift+R`).
- Check `~/.config/ghostty/config` parses by opening it in **Open Configuration…**.
- If the issue is reproducible, check `log stream` while reproducing.

## "roost" CLI not found

Run **Roost → Install CLI** from the menu. This writes a wrapper to `/usr/local/bin/roost`. Make sure `/usr/local/bin` is on your `$PATH`.

## Project won't open via `roost <path>`

The path must exist and must be a directory (not a file). Relative paths are resolved against the shell's current directory. Quote paths with spaces.

## Source Control: gh actions disabled

Pull request features require the `gh` CLI to be installed and authenticated:

```bash
brew install gh
gh auth login
```

After authenticating, restart Roost or click **Refresh** in the PR list.

## Mobile server won't start

- Make sure the port (default 4865) isn't in use: `lsof -i :4865`.
- Check **Settings → Mobile** for an error message — port conflicts and bind failures are surfaced there.

## Notifications aren't showing

- Check **Settings → Notifications** that the global toggle and the relevant per‑source toggle are on.
- macOS may have suppressed Roost's system notifications — check **System Settings → Notifications → Roost**.
- For socket-based integrations, verify the socket exists: `ls -l ~/Library/Application\ Support/Roost/roost.sock`.

## AI usage shows nothing

- Check the provider is enabled in **Settings → AI Usage**.
- Make sure the relevant credential (env var, JSON file, or Keychain entry) exists.
- Click **Refresh** in the popover and watch `log stream` for parser errors.

## Reset state

If you want to start fresh, quit Roost and remove:

```
~/Library/Application Support/Roost/
```

This wipes projects, worktrees, notifications, and approved mobile devices. Ghostty config at `~/.config/ghostty/config` is left alone.

## Reporting a bug

When filing an issue, include:

- macOS version
- Roost version (**Roost → About Roost**)
- Reproduction steps
- A `log show --predicate 'subsystem == "app.muxy"' --last 10m` snippet if relevant
