# Roost Release Checklist

This checklist tracks the current self-signed/ad-hoc local signature release path. Developer ID notarization, Sparkle appcast hosting, Homebrew distribution, telemetry, and crash reporting are future work.

## Current Release: 1.0.0 Self-Signed / Ad-Hoc ZIP

- [ ] Run `scripts/checks.sh`.
- [ ] Run `scripts/build-release.sh --arch arm64 --version 1.0.0 --zip --sign-identity -` to produce `build/Roost-1.0.0-arm64.zip`.
- [ ] Confirm `--sign-identity -` uses ad-hoc local signing and does not provide Developer ID or notarization trust.
- [ ] Verify `build/Roost-1.0.0-arm64.zip` exists.
- [ ] Verify `build/SHA256SUMS.txt` exists and contains the versioned archive.
- [ ] Verify checksum:

  ```bash
  cd build
  shasum -a 256 -c SHA256SUMS.txt
  ```

- [ ] Verify the Nix package hash if the release asset changed:

  ```bash
  nix --extra-experimental-features 'nix-command flakes' build .#packages.aarch64-darwin.default --no-link
  nix --extra-experimental-features 'nix-command flakes' build github:NextAlone/Roost/v1.0.0#packages.aarch64-darwin.default --refresh --no-link
  ```

- [ ] Verify local code signature integrity (this is not notarization or Gatekeeper trust):

  ```bash
  codesign --verify --deep --strict build/Roost.app
  ```

- [ ] Launch the app locally after removing quarantine from a copy:

  ```bash
  xattr -dr com.apple.quarantine build/Roost.app
  open build/Roost.app
  ```

## Permissions Audit

- [ ] Confirm `Muxy/Muxy.entitlements` contains only hardened-runtime code-signing exceptions needed for the self-signed/ad-hoc local signature build.
- [ ] Confirm `Muxy/Info.plist` usage descriptions are written as subprocess-triggered terminal permissions, not hidden Roost automation.
- [ ] Confirm `SUEnableAutomaticChecks` is `false` for the manual self-signed/ad-hoc local signature release path.
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
- [ ] Staple the notarization ticket to the `.app` before ZIP packaging, or to the released DMG / PKG.

## Future: Distribution

- [ ] Decide whether public distribution uses DMG, ZIP, Homebrew cask, or multiple channels.
- [ ] Decide whether Sparkle bridges from any old Muxy feed or starts as a fresh Roost feed.
- [ ] Host appcast XML on a stable URL if Sparkle is enabled.
- [ ] Generate and protect Sparkle EdDSA keys if Sparkle is enabled.
- [ ] Generate ZIP appcasts with `scripts/generate-appcast.sh build/Roost-<version>-arm64.zip v<version> <build-number> build/appcast.xml` if Sparkle is enabled.
- [ ] Define Homebrew cask auto-update strategy if Homebrew is enabled.

## Hostd Runtime

- [ ] Verify `RoostHostdXPCService.xpc` is embedded in `Roost.app/Contents/XPCServices/`.
- [ ] Verify `roost-hostd-attach` and `roost-hostd-daemon` are embedded in `Roost.app/Contents/MacOS/`.
- [ ] Smoke-test hostd-owned runtime mode on a disposable project before enabling it by default.

## Future: Telemetry and Crash Reporting

- [ ] Decide whether telemetry exists. Current decision: no telemetry.
- [ ] Document exact telemetry data before any telemetry code lands.
- [ ] Decide whether crash reporting uses system Crashlogs or a third-party SDK.
- [ ] Add user-visible debug log export before asking users for diagnostics.
