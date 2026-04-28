# Roost Release Checklist

This checklist covers the manual / human-driven items that automation cannot complete. Phase 8 (Release Readiness) of the migration plan tracks these as gates before public distribution.

## Build

- [ ] Choose Apple Developer Team ID and bundle identifier (e.g., `app.roost`).
- [ ] Generate / acquire Developer ID Application certificate.
- [ ] Wire bundle id + Team into the `.app` build (currently SPM `swift build` produces an unsigned `Roost` executable; for distribution, build via `xcodebuild` with proper Info.plist and Signing & Capabilities).
- [ ] Add Hardened Runtime flag.
- [ ] Add entitlements:
  - process spawning (terminal subprocess execution)
  - file access scope (project directories + Application Support)
  - network for `jj git fetch` (outbound HTTPS)

## Notarization

- [ ] CI workflow that codesigns + notarizes on tagged release.
- [ ] Stapled ticket attached to the released DMG / ZIP.
- [ ] App Store Connect API key for `notarytool`.

## Distribution

- [ ] App icon (`AppIcon.appiconset` + 1024px master).
- [ ] DMG packaging or ZIP archive convention.
- [ ] Sparkle appcast feed:
  - Decision: bridge from old Muxy feed or fresh-install only?
  - Host appcast XML on a stable URL.
  - EdDSA key for appcast signing.
- [ ] Homebrew cask:
  - Cask formula in `homebrew-cask` (PR upstream).
  - Auto-update strategy.

## Permissions

- [ ] Audit Info.plist usage description strings:
  - `NSAppleEventsUsageDescription` (if any AppleScript usage)
  - any other `NS*UsageDescription` keys
- [ ] First-run onboarding: explain what permissions are requested and why.

## Telemetry / Analytics

- [ ] Decision: opt-in by default (per migration plan rule).
- [ ] Decision: which SDK or in-house solution.
- [ ] Document data collected before any code lands.

## Crash Reporting

- [ ] Capture crashes via system Crashlogs OR a third-party SDK.
- [ ] User-visible export of debug logs.

## XPC Service (deferred)

- [ ] Real cross-process `RoostHostdXPCService`:
  - Build separate Xcode project (or extend with `xcodegen`) producing `.xpc` bundle.
  - Embed under `Roost.app/Contents/XPCServices/`.
  - NSXPCConnection client wraps existing `RoostHostdClient` protocol (the abstraction is already in place — only the implementation swap is needed).
  - Sandbox + entitlement story for inter-process PTY ownership.

## Pre-Release Smoke

- [ ] `scripts/checks.sh` clean.
- [ ] Manual session lifecycle smoke:
  - Create + close project
  - Create + remove workspace
  - Open agent tab → exit Claude → re-launch from history
  - Open VCS panel on jj repo → describe / new / commit / squash / abandon
  - Bookmark create / move / delete
- [ ] Re-test on the lowest supported macOS version (14.0).
