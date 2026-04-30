# Roost Permissions Design

## Background and Target

Roost is a macOS-native terminal orchestrator for jj workspaces and coding agents. The current release path is self-signed distribution, not Developer ID notarization. The permissions design must therefore separate two concerns:

- What Roost needs to run safely as a local developer tool today.
- What future notarized or XPC-based releases must revisit later.

The target for the current release is a self-signed, non-notarized macOS app distributed as a manual download. Roost should request or declare only permissions that match real behavior, document the trust model clearly, and avoid telemetry or crash-reporting work for now.

## Core Principles

- Roost is a terminal host. Commands launched inside Roost can trigger macOS privacy prompts independently of Roost's own UI.
- Roost should not claim access it does not directly need.
- Self-signed builds must be explicit about Gatekeeper and quarantine handling.
- Secrets stay out of `.roost/config.json`; Keychain-backed env values are resolved at launch time and never persisted as plaintext.
- Network activity is user-driven or tool-driven. Roost does not add telemetry in the current release.
- Future XPC hostd work gets a separate entitlement and sandbox design. The current release keeps the hostd path in-process.

## Current State

| Area | Current artifact | Observation |
|---|---|---|
| Bundle metadata | `Muxy/Info.plist` | Contains broad `NS*UsageDescription` keys for Apple Events, Bluetooth, calendar, camera, contacts, local network, location, microphone, motion, photos, reminders, speech recognition, and system administration. |
| Entitlements | `Muxy/Muxy.entitlements` | Contains Apple Events, JIT / unsigned executable memory / disable library validation, camera, audio input, network server, contacts, calendars, location, and photos entitlements. |
| Release script | `scripts/build-release.sh` | Builds an app bundle, embeds Sparkle, optionally signs the app and DMG, and always creates a DMG through `create-dmg`. It still uses git for build number calculation and Muxy bundle names in some paths. |
| Updates | `Muxy/Services/UpdateService.swift` | Sparkle is present and can start if configured. The self-signed release path should not rely on Sparkle as the default update mechanism. |
| Config secrets | `RoostConfigEnvResolver`, `AIUsageTokenReader` | Keychain values are read through `/usr/bin/security`; missing entries are skipped. |
| Notifications | `NotificationStore` | Notifications are app-local records plus sound/toast behavior, not system `UNUserNotificationCenter` notifications. |

## Release Permission Model

The current release should be documented as a self-signed developer build:

- Build output: `Roost.app.zip` is preferred over DMG for the first self-signed release.
- Signing: ad-hoc or local self-signed identity only.
- Notarization: not available without Developer ID and intentionally out of scope.
- Installation: users unzip, move `Roost.app` to `/Applications`, then approve Gatekeeper manually or remove quarantine with `xattr -dr com.apple.quarantine /Applications/Roost.app`.
- Updates: manual download and replace. Sparkle remains a code dependency but is not the current distribution contract.
- Verification: publish `SHA256SUMS.txt` beside the archive.

This model avoids implying that the app has passed Apple's Developer ID review or notarization checks.

## Permission Areas

### Files and Project Directories

Roost accesses project directories selected by the user and stores app state under Application Support. Project config lives at `.roost/config.json`, with legacy setup fallback from `.muxy/worktree.json`.

Design rules:

- No sandbox security-scoped bookmark implementation is required for the current non-sandbox self-signed release.
- If a future sandboxed release is attempted, project directory access must be redesigned around security-scoped bookmarks.
- `.roost/config.json` writes continue to use `0600` permissions, and `.roost/` uses `0700`.

### Subprocess Execution

Roost launches terminal shells, coding-agent CLIs, `jj`, setup commands, teardown commands, and notification hook helpers. These subprocesses run with the user's privileges.

Design rules:

- Roost must treat subprocess execution as intentional developer-tool behavior, not a hidden background capability.
- Setup and teardown failures should surface through existing logs / UI paths without leaking secret env values.
- `jj` invocations keep the existing controlled environment contract from the migration plan.
- No sandbox entitlement can make arbitrary developer subprocesses safe by itself; this is a trust-boundary statement for documentation.

### Keychain

Roost supports config env values such as:

```json
{
  "API_TOKEN": { "fromKeychain": "roost-api-token", "account": "default" }
}
```

Design rules:

- Roost reads Keychain values at launch time through the existing resolver path.
- Secret values are passed only to the target setup command or agent process environment.
- Secret values are not written back to `.roost/config.json`, logs, notifications, or persisted session records.
- Missing Keychain items remain non-fatal and should be visible as actionable warnings where the invoking workflow already has an error surface.

### Network

Roost itself may initiate or enable network activity through:

- `jj git fetch` / `jj git push`.
- Coding-agent CLIs launched in terminal panes.
- Remote / mobile server features when enabled.
- Sparkle if a future update feed is configured.

Design rules:

- No telemetry or analytics are added in the current release.
- README / release docs should state that agent CLIs and user commands may contact external services under their own configuration.
- Sparkle update checks should be treated as disabled / unconfigured for the self-signed manual distribution path unless a feed is explicitly provided.

### Notifications

Current Roost notifications are in-app notification records, sidebar badges, sounds, and optional toast behavior. They are not macOS system notifications.

Design rules:

- No `NSUserNotification` / `UNUserNotificationCenter` permission prompt is required for the current notification implementation.
- Documentation should avoid implying that Roost needs macOS Notification Center permission unless that implementation changes.
- Notification content may include command or agent output snippets, so logs and remote APIs must keep existing truncation and privacy constraints.

### Apple Events and Automation

Roost does not currently need to control other apps from its own UI. A shell command or agent process running inside Roost may invoke AppleScript and trigger macOS automation prompts.

Design rules:

- Roost should not present Apple Events as a first-class app feature in the current release.
- If `NSAppleEventsUsageDescription` remains in `Info.plist`, the wording should say it exists for processes launched inside Roost, not for hidden Roost automation.
- Direct Roost-controlled Apple Events require a separate feature design.

### Camera, Microphone, Contacts, Calendars, Photos, Location, Bluetooth, Motion, Speech, Reminders

The current app does not expose first-class Roost features for these privacy domains. They may only be requested by arbitrary subprocesses running inside terminal panes.

Design rules:

- These should not be treated as Roost product permissions.
- The current broad `Info.plist` descriptions and broad personal-information entitlements need audit before release.
- For the self-signed non-sandbox release, prefer removing entitlements that are not required by the app bundle itself.
- If macOS requires usage descriptions because terminal child processes can trigger TCC prompts under Roost's bundle, keep the descriptions but make them subprocess-specific and user-readable.

### XPC Hostd

The real cross-process `RoostHostdXPCService` remains deferred.

Design rules:

- Do not block the self-signed release on XPC hostd entitlements.
- Future XPC design must define the service bundle id, code signing path, sandbox profile, PTY ownership model, and attach/release protocol separately.
- The existing `RoostHostdClient` boundary is the integration seam for that later work.

## Functional Design

### Permission Audit Document

Add a concise release-facing permission document after this spec is approved. It should explain:

- Why Roost launches subprocesses.
- What project files Roost reads and writes.
- How Keychain references work.
- What network activity may occur.
- Why the current build is self-signed and non-notarized.
- What users must do if Gatekeeper blocks launch.

### Build and Release Checklist Updates

Update `RELEASE-CHECKLIST.md` after approval:

- Replace Developer ID notarization as the current path with self-signed manual distribution.
- Move notarization, Sparkle feed, Homebrew cask, telemetry, crash reporting, and XPC hostd to future work.
- Add ZIP + SHA256 release artifacts.
- Add quarantine / Gatekeeper documentation.
- Add an entitlement / `Info.plist` audit task before publishing.

### Entitlement and Info.plist Audit

Implementation should inspect actual runtime needs before removing keys. The expected end state is:

- Minimal entitlements for the self-signed app.
- Usage descriptions aligned with real behavior.
- No broad personal-information entitlement unless a concrete Roost feature requires it.
- No sandbox entitlement unless a separate sandbox design exists.

## Impact Scope

| Area | Impact |
|---|---|
| Release docs | Add self-signed install and verification instructions. |
| `RELEASE-CHECKLIST.md` | Reclassify current vs future release gates. |
| `Muxy/Info.plist` | Audit broad usage descriptions and keep only justified text. |
| `Muxy/Muxy.entitlements` | Audit broad entitlements before release signing. |
| `scripts/build-release.sh` | Later implementation may add ZIP output, SHA256 generation, and self-signed defaults. |
| Sparkle | Remains present but not the current update contract. |
| XPC hostd | Deferred; no current implementation change. |

## Risks

| Risk | Mitigation |
|---|---|
| Users confuse self-signed with notarized | Release docs must explicitly say the build is self-signed and non-notarized. |
| Overbroad entitlements imply unnecessary privacy access | Audit entitlements before publishing and remove unjustified keys. |
| Removing a usage description breaks child-process TCC prompts | Test common terminal workflows after each `Info.plist` reduction. |
| Sparkle appears enabled without a feed strategy | Document manual updates as the current path and avoid presenting Sparkle as supported release infrastructure. |
| Keychain values leak through env display or logs | Keep secret redaction rules and avoid logging resolved env maps. |
| Future sandbox work conflicts with terminal behavior | Treat sandboxing as a separate design, not a checklist toggle. |

## Test Points

- Build a release app bundle with self-signed or ad-hoc signing.
- Verify `codesign --verify --deep --strict` passes for the produced app.
- Verify first launch behavior on a quarantined app and document the exact Gatekeeper path.
- Verify `xattr -dr com.apple.quarantine Roost.app` allows launch when Gatekeeper blocks.
- Open a project, create a jj workspace, launch a terminal, and run `jj status`.
- Run setup and teardown commands with plain env and Keychain-backed env.
- Confirm missing Keychain entries do not crash the workflow.
- Confirm no telemetry or crash-reporting network request exists in the current release path.
- Confirm Sparkle update UI is not promised in release docs unless a feed is configured.
- Run `scripts/checks.sh` after any implementation change.

## Out of Scope

- Developer ID notarization.
- Sparkle appcast hosting and automatic updates.
- Homebrew cask submission.
- Telemetry and analytics.
- Crash-reporting SDK integration.
- Real cross-process `RoostHostdXPCService`.
- Sandboxed app redesign.
