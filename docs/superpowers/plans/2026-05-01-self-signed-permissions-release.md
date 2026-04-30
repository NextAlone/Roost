# Self-Signed Permissions Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert Roost's release preparation from Developer ID notarization assumptions to a self-signed manual distribution path with clear permission documentation and tighter entitlements.

**Architecture:** Keep Roost non-sandboxed for the current release. Document the terminal-host trust model, keep usage descriptions that may be needed for subprocess-triggered TCC prompts, remove privacy-domain entitlements from the app signing profile, and make the release checklist reflect ZIP + SHA256 manual distribution. Sparkle, XPC hostd, telemetry, crash reporting, Homebrew, and notarization remain future work.

**Tech Stack:** macOS app bundle, Swift Package Manager, `Info.plist`, codesign entitlements plist, shell release script, Markdown docs, `plutil`, `codesign`, `shasum`.

---

## File Structure

- `docs/permissions.md` — release-facing explanation of Roost's permissions, subprocess trust model, Keychain behavior, network behavior, and self-signed Gatekeeper flow.
- `README.md` — concise release section pointing to the self-signed install path and `docs/permissions.md`.
- `RELEASE-CHECKLIST.md` — current release checklist rewritten around self-signed ZIP distribution and future-work sections.
- `Muxy/Info.plist` — keep terminal-subprocess usage descriptions, update Sparkle automatic checks to false for manual distribution, and tighten confusing wording.
- `Muxy/Muxy.entitlements` — remove privacy / personal-information / network-server / Apple Events entitlements; keep only hardened-runtime code-signing exceptions already used by the signing flow.
- `scripts/build-release.sh` — add a self-signed ZIP + SHA256 path, remove git dependency for build number, fix Roost bundle names, make DMG optional, and keep Sparkle feed injection opt-in.
- `docs/roost-migration-plan.md` — append a short Phase 8 follow-up status note for self-signed release preparation.

## Task 1: Release-Facing Permissions Document

**Files:**
- Create: `docs/permissions.md`
- Modify: `README.md`

- [ ] **Step 1: Create `docs/permissions.md`**

Add this file exactly:

```markdown
# Roost Permissions

Roost is a macOS terminal host for jj workspaces and coding agents. It launches shells, agent CLIs, `jj`, setup commands, teardown commands, and notification helpers on your behalf.

## Current Release Trust Model

The current Roost release is self-signed and non-notarized. It is intended for users who understand that macOS will not show the same trust signal as a Developer ID notarized app.

Install flow:

1. Download `Roost.app.zip` and `SHA256SUMS.txt` from the release.
2. Verify the archive:

   ```bash
   shasum -a 256 -c SHA256SUMS.txt
   ```

3. Unzip `Roost.app.zip`.
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

Roost reads these values at launch time and passes them only to the configured setup command or agent process. Roost does not write resolved secret values back to config, logs, notifications, or session records.

## Network

Roost does not include telemetry or analytics in the current release.

Network activity can still happen through commands you run, coding agents, `jj git fetch`, `jj git push`, remote/mobile features when enabled, or future update infrastructure if configured.

## Notifications

Current Roost notifications are in-app records, badges, sounds, and optional toast UI. They are not macOS Notification Center notifications.

## Updates

The current release uses manual updates. Download a newer `Roost.app.zip`, verify its SHA256 checksum, quit Roost, and replace the app.

Sparkle is still present in the codebase, but automatic updates are not the current self-signed distribution contract.

## Future Work

Developer ID notarization, Sparkle appcast hosting, Homebrew cask distribution, crash reporting, telemetry, sandboxing, and the real XPC host daemon are separate future designs.
```

- [ ] **Step 2: Update README release section**

Replace the current `## Release` section in `README.md`:

```markdown
## Release

See [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) for the manual handoff items (signing, notarization, telemetry, distribution).
```

with:

```markdown
## Release

The current release path is self-signed, non-notarized, and manually distributed as `Roost.app.zip` plus `SHA256SUMS.txt`.

See [docs/permissions.md](docs/permissions.md) for the trust model and install notes. See [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) for release gates and future distribution work.
```

- [ ] **Step 3: Verify Markdown references**

Run:

```bash
rg -n "docs/permissions.md|Roost.app.zip|SHA256SUMS" README.md docs/permissions.md
```

Expected: matches in both files.

- [ ] **Step 4: Commit**

Run:

```bash
jj --config ui.paginate=never --config ui.color=never commit -m "docs(release): document self-signed permissions model"
```

## Task 2: Release Checklist Rewrite

**Files:**
- Modify: `RELEASE-CHECKLIST.md`

- [ ] **Step 1: Replace `RELEASE-CHECKLIST.md`**

Replace the whole file with:

```markdown
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
```

- [ ] **Step 2: Verify current vs future sections**

Run:

```bash
rg -n "Current Release|Future: Developer ID|Current decision: no telemetry|Roost.app.zip|SUEnableAutomaticChecks" RELEASE-CHECKLIST.md
```

Expected: one or more matches for each phrase.

- [ ] **Step 3: Commit**

Run:

```bash
jj --config ui.paginate=never --config ui.color=never commit -m "docs(release): rewrite checklist for self-signed zip"
```

## Task 3: Tighten Bundle Metadata and Entitlements

**Files:**
- Modify: `Muxy/Info.plist`
- Modify: `Muxy/Muxy.entitlements`

- [ ] **Step 1: Update Sparkle automatic checks**

In `Muxy/Info.plist`, change:

```xml
	<key>SUEnableAutomaticChecks</key>
	<true/>
```

to:

```xml
	<key>SUEnableAutomaticChecks</key>
	<false/>
```

- [ ] **Step 2: Tighten privacy usage descriptions**

Keep the existing `NS*UsageDescription` keys, because terminal child processes can trigger TCC prompts under Roost's bundle. Replace the strings with this subprocess-specific wording:

```xml
	<key>NSAppleEventsUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting Apple Events automation.</string>
	<key>NSBluetoothAlwaysUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting Bluetooth access.</string>
	<key>NSCalendarsUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting calendar access.</string>
	<key>NSCameraUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting camera access.</string>
	<key>NSContactsUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting contacts access.</string>
	<key>NSLocalNetworkUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting local network access.</string>
	<key>NSLocationUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting location access.</string>
	<key>NSMicrophoneUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting microphone access.</string>
	<key>NSMotionUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting motion data access.</string>
	<key>NSPhotoLibraryUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting photo library access.</string>
	<key>NSRemindersUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting reminders access.</string>
	<key>NSSpeechRecognitionUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting speech recognition access.</string>
	<key>NSSystemAdministrationUsageDescription</key>
	<string>A command or agent running in Roost's terminal is requesting administrator privileges.</string>
```

- [ ] **Step 3: Replace entitlements with hardened-runtime exceptions only**

Replace `Muxy/Muxy.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
	<key>com.apple.security.cs.allow-unsigned-executable-memory</key>
	<true/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
</dict>
</plist>
```

This intentionally removes Apple Events, camera, audio input, contacts, calendars, location, photos, and network-server entitlements. Those are not first-class Roost app capabilities in the self-signed release.

- [ ] **Step 4: Validate plist syntax**

Run:

```bash
plutil -lint Muxy/Info.plist Muxy/Muxy.entitlements
```

Expected:

```text
Muxy/Info.plist: OK
Muxy/Muxy.entitlements: OK
```

- [ ] **Step 5: Verify entitlement key set**

Run:

```bash
plutil -p Muxy/Muxy.entitlements
```

Expected output contains only:

```text
"com.apple.security.cs.disable-library-validation" => true
"com.apple.security.cs.allow-unsigned-executable-memory" => true
"com.apple.security.cs.allow-jit" => true
```

- [ ] **Step 6: Commit**

Run:

```bash
jj --config ui.paginate=never --config ui.color=never commit -m "chore(release): tighten self-signed entitlements"
```

## Task 4: Self-Signed ZIP Release Script

**Files:**
- Modify: `scripts/build-release.sh`

- [ ] **Step 1: Add mode flags and update usage**

At the top of `scripts/build-release.sh`, after:

```bash
SPARKLE_FEED_URL=""
```

add:

```bash
PACKAGE_FORMAT="zip"
BUILD_NUMBER=""
```

In the argument parser, add these cases before the default `*)` case:

```bash
        --zip)
            PACKAGE_FORMAT="zip"
            shift
            ;;
        --dmg)
            PACKAGE_FORMAT="dmg"
            shift
            ;;
        --build-number)
            BUILD_NUMBER="$2"
            shift 2
            ;;
```

Replace the usage string:

```bash
echo "Usage: $0 --arch <arm64|x86_64> --version <X.Y.Z> [--sign-identity <identity>] [--sparkle-public-key <key>] [--sparkle-feed-url <url>]"
```

with:

```bash
echo "Usage: $0 --arch <arm64|x86_64> --version <X.Y.Z> [--zip|--dmg] [--build-number <number>] [--sign-identity <identity>] [--sparkle-public-key <key>] [--sparkle-feed-url <url>]"
```

- [ ] **Step 2: Remove git dependency for build number**

Replace:

```bash
BUILD_NUMBER=$(git -C "$PROJECT_ROOT" rev-list --count HEAD)
APP_BUNDLE="$BUILD_DIR/Muxy.app"
DMG_NAME="Muxy-${VERSION}-${ARCH}.dmg"
```

with:

```bash
if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
fi

APP_BUNDLE="$BUILD_DIR/Roost.app"
ZIP_NAME="Roost-${VERSION}-${ARCH}.zip"
DMG_NAME="Roost-${VERSION}-${ARCH}.dmg"
```

- [ ] **Step 3: Copy the correct executable name**

Replace:

```bash
cp "$SPM_BUILD_DIR/Muxy" "$APP_BUNDLE/Contents/MacOS/Muxy"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/Muxy"
```

with:

```bash
cp "$SPM_BUILD_DIR/Roost" "$APP_BUNDLE/Contents/MacOS/Roost"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/Roost"
```

Replace:

```bash
strip -Sx "$APP_BUNDLE/Contents/MacOS/Muxy"
```

with:

```bash
strip -Sx "$APP_BUNDLE/Contents/MacOS/Roost"
```

- [ ] **Step 4: Copy the current resource bundle name**

Replace:

```bash
if [[ -d "$SPM_BUILD_DIR/Muxy_Muxy.bundle" ]]; then
    cp -R "$SPM_BUILD_DIR/Muxy_Muxy.bundle" "$APP_BUNDLE/Contents/Resources/Muxy_Muxy.bundle"
fi
```

with:

```bash
if [[ -d "$SPM_BUILD_DIR/Roost_Roost.bundle" ]]; then
    cp -R "$SPM_BUILD_DIR/Roost_Roost.bundle" "$APP_BUNDLE/Contents/Resources/Roost_Roost.bundle"
elif [[ -d "$SPM_BUILD_DIR/Muxy_Muxy.bundle" ]]; then
    cp -R "$SPM_BUILD_DIR/Muxy_Muxy.bundle" "$APP_BUNDLE/Contents/Resources/Muxy_Muxy.bundle"
fi
```

- [ ] **Step 5: Add ZIP packaging and SHA256 generation**

Replace everything from:

```bash
echo "==> Creating DMG"
```

through the end of the file with:

```bash
if [[ "$PACKAGE_FORMAT" == "zip" ]]; then
    echo "==> Creating ZIP"
    cd "$BUILD_DIR"
    rm -f "$ZIP_NAME" SHA256SUMS.txt
    /usr/bin/ditto -c -k --keepParent "Roost.app" "$ZIP_NAME"
    shasum -a 256 "$ZIP_NAME" > SHA256SUMS.txt
    echo "==> Done: $BUILD_DIR/$ZIP_NAME"
    echo "==> Checksum: $BUILD_DIR/SHA256SUMS.txt"
    exit 0
fi

if [[ "$PACKAGE_FORMAT" != "dmg" ]]; then
    echo "Error: package format must be zip or dmg"
    exit 1
fi

echo "==> Creating DMG"
if ! command -v create-dmg &> /dev/null; then
    echo "Error: create-dmg not found. Install with: npm install --global create-dmg"
    exit 1
fi

cd "$BUILD_DIR"
create-dmg "$APP_BUNDLE" "$BUILD_DIR" || true

GENERATED_DMG=$(find "$BUILD_DIR" -maxdepth 1 -name "Roost*.dmg" -not -name "$DMG_NAME" | head -1)
if [[ -n "$GENERATED_DMG" ]]; then
    mv "$GENERATED_DMG" "$BUILD_DIR/$DMG_NAME"
fi

if [[ -n "$SIGN_IDENTITY" && -f "$BUILD_DIR/$DMG_NAME" ]]; then
    echo "==> Signing DMG"
    /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$BUILD_DIR/$DMG_NAME"
fi

echo "==> Done: $BUILD_DIR/$DMG_NAME"
```

- [ ] **Step 6: Shell syntax check**

Run:

```bash
bash -n scripts/build-release.sh
```

Expected: no output and exit code 0.

- [ ] **Step 7: Commit**

Run:

```bash
jj --config ui.paginate=never --config ui.color=never commit -m "chore(release): add self-signed zip packaging"
```

## Task 5: Migration Plan Follow-Up Note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append Phase 8 follow-up**

In `docs/roost-migration-plan.md`, after the existing Phase 8 status block that ends with:

```markdown
- **Phase 8 engineering work complete.** Distribution gates (Apple Developer Team ID, signing identity, notarization CI, app icon, Sparkle hosting, Homebrew cask submission) are tracked in `RELEASE-CHECKLIST.md` as human follow-up.
```

append:

```markdown

**Follow-up status (2026-05-01): self-signed release path designed.**

- Current release target is self-signed, non-notarized, manually distributed as `Roost.app.zip` with `SHA256SUMS.txt`.
- Developer ID notarization, Sparkle feed hosting, Homebrew cask distribution, telemetry, crash reporting, and real XPC hostd remain future work.
- Permission model documented in `docs/permissions.md`: Roost is a terminal host, subprocesses can trigger macOS privacy prompts, Keychain env values are resolved at launch time and not persisted as plaintext.
```

- [ ] **Step 2: Verify status note**

Run:

```bash
rg -n "self-signed release path|Roost.app.zip|docs/permissions.md" docs/roost-migration-plan.md
```

Expected: three matching lines in the Phase 8 section.

- [ ] **Step 3: Commit**

Run:

```bash
jj --config ui.paginate=never --config ui.color=never commit -m "docs(plan): note self-signed release path"
```

## Task 6: Verification Pass

**Files:**
- No planned source edits. Commit only if format tooling changes files.

- [ ] **Step 1: Validate plists and shell**

Run:

```bash
plutil -lint Muxy/Info.plist Muxy/Muxy.entitlements
bash -n scripts/build-release.sh
```

Expected:

```text
Muxy/Info.plist: OK
Muxy/Muxy.entitlements: OK
```

and no shell syntax output.

- [ ] **Step 2: Run full checks**

Run:

```bash
scripts/checks.sh
```

Expected: formatting, linting, and build pass.

- [ ] **Step 3: Build self-signed ZIP smoke**

Run:

```bash
scripts/build-release.sh --arch arm64 --version 0.1.0 --zip
```

Expected:

```text
==> Done: .../build/Roost-0.1.0-arm64.zip
==> Checksum: .../build/SHA256SUMS.txt
```

- [ ] **Step 4: Verify release artifacts**

Run:

```bash
test -d build/Roost.app
test -f build/Roost-0.1.0-arm64.zip
test -f build/SHA256SUMS.txt
cd build && shasum -a 256 -c SHA256SUMS.txt
```

Expected:

```text
Roost-0.1.0-arm64.zip: OK
```

- [ ] **Step 5: Verify app signature if signed**

If Task 6 Step 3 used `--sign-identity`, run:

```bash
codesign --verify --deep --strict build/Roost.app
```

Expected: no output and exit code 0.

If no `--sign-identity` was used, skip this step and note that the archive is unsigned / ad-hoc for local testing only.

- [ ] **Step 6: Inspect final diff**

Run:

```bash
jj --config ui.paginate=never --config ui.color=never diff --git
```

Expected: no unrelated changes.

- [ ] **Step 7: Commit verification fixes if needed**

If `scripts/checks.sh` or formatting changes files, commit them:

```bash
jj --config ui.paginate=never --config ui.color=never commit -m "chore(release): finalize self-signed release prep"
```

If no files changed, do not create an empty commit.

## Spec Coverage

| Spec requirement | Covered by |
|---|---|
| Self-signed, non-notarized trust model | Tasks 1, 2, 4 |
| Manual ZIP + SHA256 distribution | Tasks 1, 2, 4, 6 |
| Files and project directory behavior | Task 1 |
| Subprocess trust boundary | Task 1 |
| Keychain secret handling | Task 1 |
| Network with no telemetry | Tasks 1, 2 |
| In-app notifications only | Task 1 |
| Apple Events / TCC subprocess wording | Tasks 1, 3 |
| Broad privacy entitlement audit | Task 3 |
| XPC hostd deferred | Tasks 1, 2, 5 |
| Release checklist updates | Task 2 |
| Build script ZIP path | Task 4 |
| Verification commands | Task 6 |

## Placeholder Scan

No placeholders are permitted in this plan. The plan intentionally uses concrete file paths, exact replacement text, exact commands, and expected outputs.

## Abort Criteria

Stop and revisit the design if either condition occurs:

- Removing the privacy-domain entitlements prevents a basic signed app launch or terminal tab creation.
- Keeping the subprocess-oriented `NS*UsageDescription` keys still causes macOS to terminate a common child-process TCC request before showing a prompt.
