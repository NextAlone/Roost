# Privacy Policy

_Effective date: the date this document was first published at its public URL._

Roost is a macOS developer tool that hosts terminals, jj workspaces, coding-agent CLIs, optional local remote-server features, and local notification hooks. This policy describes what Roost itself stores and what it does not collect.

## Summary

- No Roost account, sign-up, or email is required.
- Roost does not include telemetry, advertising, or third-party tracking SDKs in the current release.
- Project files, workspace metadata, settings, notifications, and session records are stored locally.
- Commands, shells, agents, and `jj git` operations you run inside Roost may contact external services under their own configuration.

## Local Data

Roost may store the following on your Mac:

- **Projects and workspace state.** Opened project paths, workspace/worktree metadata, tabs, splits, editor state, and related app state under `~/Library/Application Support/Roost/`.
- **Roost configuration.** App-wide config at `~/Library/Application Support/Roost/config.json` and project config at `<project>/.roost/config.json`.
- **Session history.** Local host/session records under `~/Library/Application Support/Roost/hostd/`.
- **Notifications.** In-app notification records, badges, sounds, and toast state. Notification content may include truncated command or agent output.
- **Remote-server approvals.** If the local remote/mobile server is enabled, approved device records are stored locally.

## Keychain References

`.roost/config.json` can reference macOS Keychain items by service and optional account. Roost resolves those references when launching configured setup commands, teardown commands, or agent processes. Roost does not write resolved secret values back to config, notifications, or session records.

Commands launched in terminal panes run under your user account. If a command or shell echoes environment variables, those values can appear in terminal output or scrollback.

## Network Activity

Roost itself does not send analytics or telemetry in the current release.

Network activity can still happen through:

- Commands you run in terminals
- Coding-agent CLIs
- `jj git fetch`, `jj git push`, or other VCS operations
- Optional local remote/mobile server features when enabled
- Future update infrastructure if configured in a later release

The remote/mobile server is intended for trusted local networks or private tunnels such as Tailscale or a VPN. It is disabled by default.

## What Roost Does Not Collect

- No Roost account identity.
- No usage analytics or advertising identifiers.
- No contacts, photos, location, microphone, or camera data collected by Roost itself.
- No telemetry or crash-reporting upload in the current release.
- No sale of personal data.

## Permissions

Roost is a terminal host. Commands and agents running inside Roost can trigger macOS privacy prompts under Roost's bundle. See [docs/permissions.md](docs/permissions.md) for the current trust and permission model.

## Updates

The current release uses manual updates. Sparkle is bundled in the codebase, but automatic update delivery is not the current self-signed/ad-hoc release contract.

## Children

Roost is a developer tool and is not directed to children under 13.

## Changes to this policy

If this policy changes, the updated version will be posted at this URL with a new "Last updated" date.

## Contact

Questions about this policy: sa.vaziry@gmail.com
