# Roost Permissions

Roost is a macOS terminal host for jj workspaces and coding agents. It launches shells, agent CLIs, `jj`, setup commands, teardown commands, and notification helpers on your behalf.

## Current Release Trust Model

The current Roost archive uses a self-signed/ad-hoc local signature and is non-notarized. It is intended for users who understand that macOS will not show Developer ID trust or the same trust signal as a Developer ID notarized app.

Install flow:

1. Download `Roost-<version>-<arch>.zip` and `SHA256SUMS.txt` from the release.
2. Verify the archive:

   ```bash
   shasum -a 256 -c SHA256SUMS.txt
   ```

3. Unzip `Roost-<version>-<arch>.zip`.
4. Move `Roost.app` to `/Applications`.
5. If Gatekeeper blocks launch, either approve the app in System Settings or remove the quarantine attribute:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Roost.app
   ```

## Files

Roost reads and writes files in project directories you open. Project config lives at `<project>/.roost/config.json`. Roost creates `.roost/` with `0700` permissions and `config.json` with `0600` permissions when it writes the file.

Roost also stores app state under your Application Support directory.

## Subprocesses

Roost is a terminal app. Commands running inside Roost run with your user privileges and can trigger macOS privacy prompts under Roost's bundle. Examples include shell commands, coding-agent CLIs, setup / teardown commands, notification hook scripts, and `jj` operations.

Roost does not hide this as a background permission. If a command or agent accesses files, the network, Apple Events, camera, microphone, or other protected resources, that access is caused by the command you launched or configured.

## Keychain

`.roost/config.json` can reference Keychain items:

```json
{
  "API_TOKEN": { "fromKeychain": "roost-api-token", "account": "default" }
}
```

Roost resolves these values when launching configured setup commands, teardown commands, or agent processes. Roost does not write resolved secret values back to config, notifications, or session records.

Commands run inside terminal panes with your user privileges. If a shell command or agent echoes environment variables, those values can appear in terminal output or scrollback.

## Network

Roost does not include telemetry or analytics in the current release.

Network activity can still happen through commands you run, coding agents, `jj git fetch`, `jj git push`, remote/mobile features when enabled, or future update infrastructure if configured.

## Notifications

Current Roost notifications are in-app records, badges, sounds, and optional toast UI. They are not macOS Notification Center notifications.

## Updates

The current release uses manual updates. Download a newer `Roost-<version>-<arch>.zip`, verify its SHA256 checksum, quit Roost, and replace the app.

Sparkle is still present in the codebase, but automatic updates are not the current self-signed/ad-hoc local signature distribution contract.

## Future Work

Developer ID notarization, Sparkle appcast hosting, Homebrew cask distribution, crash reporting, telemetry, sandboxing, and the real XPC host daemon are separate future designs.
