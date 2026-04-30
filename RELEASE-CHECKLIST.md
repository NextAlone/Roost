# Roost Release Checklist

This checklist tracks the current self-signed release path. Developer ID notarization, Sparkle appcast hosting, Homebrew distribution, telemetry, crash reporting, and the real XPC host daemon are future work.

## Current Release: Self-Signed ZIP

- [ ] Run `scripts/checks.sh`.
- [ ] Build `Roost.app.zip` with `scripts/build-release.sh --arch arm64 --version <X.Y.Z> --zip`.
- [ ] Verify `build/Roost.app.zip` exists.
- [ ] Verify `build/SHA256SUMS.txt` exists and contains `Roost.app.zip`.
- [ ] Verify checksum:

  ```bash
  cd build
  shasum -a 256 -c SHA256SUMS.txt
  ```

- [ ] Verify app signature:

  ```bash
  codesign --verify --deep --strict build/Roost.app
  ```

- [ ] Launch the app locally after removing quarantine from a copy:

  ```bash
  xattr -dr com.apple.quarantine build/Roost.app
  open build/Roost.app
  ```

## Permissions Audit

- [ ] Confirm `Muxy/Muxy.entitlements` contains only hardened-runtime code-signing exceptions needed for the self-signed build.
- [ ] Confirm `Muxy/Info.plist` usage descriptions are written as subprocess-triggered terminal permissions, not hidden Roost automation.
- [ ] Confirm `SUEnableAutomaticChecks` is `false` for the manual self-signed release path.
- [ ] Confirm [docs/permissions.md](docs/permissions.md) documents files, subprocesses, Keychain, network, notifications, manual updates, and Gatekeeper.

## Manual Smoke

- [ ] Open a jj project.
- [ ] Create and remove a workspace.
- [ ] Open a plain terminal tab and run `jj status`.
- [ ] Open an agent tab, exit it, and re-launch it from history.
- [ ] Open the jj VCS panel and run describe / new / commit / squash / abandon on a disposable repo.
- [ ] Create, move, and delete a bookmark on a disposable repo.
- [ ] Run setup and teardown commands using a disposable `.roost/config.json`.
- [ ] Run a setup command with a missing Keychain env reference and confirm the workflow does not crash.
- [ ] Re-test on the lowest supported macOS version, 14.0, before publishing outside local machines.

## Future: Developer ID / Notarization

- [ ] Choose Apple Developer Team ID and final bundle identifier.
- [ ] Generate or acquire Developer ID Application certificate.
- [ ] Wire Team ID into an Xcode or equivalent app build.
- [ ] Add Hardened Runtime release settings.
- [ ] Add notarization CI with `notarytool`.
- [ ] Staple the notarization ticket to the released DMG or ZIP.

## Future: Distribution

- [ ] Decide whether public distribution uses DMG, ZIP, Homebrew cask, or multiple channels.
- [ ] Decide whether Sparkle bridges from any old Muxy feed or starts as a fresh Roost feed.
- [ ] Host appcast XML on a stable URL if Sparkle is enabled.
- [ ] Generate and protect Sparkle EdDSA keys if Sparkle is enabled.
- [ ] Define Homebrew cask auto-update strategy if Homebrew is enabled.

## Future: XPC Service

- [ ] Build `RoostHostdXPCService` as a separate `.xpc` bundle.
- [ ] Embed it under `Roost.app/Contents/XPCServices/`.
- [ ] Implement `NSXPCConnection` client behind the existing `RoostHostdClient` protocol.
- [ ] Define sandbox and entitlement boundaries for inter-process PTY ownership.

## Future: Telemetry and Crash Reporting

- [ ] Decide whether telemetry exists. Current decision: no telemetry.
- [ ] Document exact telemetry data before any telemetry code lands.
- [ ] Decide whether crash reporting uses system Crashlogs or a third-party SDK.
- [ ] Add user-visible debug log export before asking users for diagnostics.
