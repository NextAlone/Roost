# Phase 8 — Release Readiness (Engineering Subset)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development.

**Goal:** Cover the engineering-doable subset of Phase 8: third-party license attribution, README updates, and a final clean checks pass. Human-driven items (app icon, Apple Developer signing identity, notarization CI, Sparkle feed, Homebrew cask, telemetry) are explicitly documented as out-of-scope and routed to a follow-up release-engineering checklist.

**Architecture:** No code changes — pure documentation + content authoring. The point is to make the repo look like a serious app: license attributions present, README explains how to build/use, and the checks script passes from a clean state.

**Tech Stack:** Markdown, no Swift changes.

**Locked decisions:**
- Phase 8 work in this plan covers **content + docs only**. Any platform / signing / distribution work is explicitly deferred and documented as a `RELEASE-CHECKLIST.md` for human follow-up.
- Third-party licenses are bundled in a single `THIRD_PARTY_LICENSES.md` at repo root, indexed by package, with each license's verbatim text.
- README adds an "Architecture overview" pointer (already exists in `docs/architecture.md`) plus a sessions/agent quickstart.
- No telemetry / analytics code added in this phase.

**Out of scope (documented as `RELEASE-CHECKLIST.md` items):**
- App icon design + asset bundling
- Apple Developer Team ID + bundle id selection
- Hardened runtime entitlements
- Notarization CI pipeline (codesign + notary)
- Sparkle feed migration (existing Muxy → Roost)
- Homebrew cask submission
- Crash reporter integration (Sentry / Bugsnag / system Crashlogs export)
- Telemetry / analytics SDK
- Permission usage descriptions (`NSAppleEventsUsageDescription` etc.)

---

## File Structure

**Create:**
- `THIRD_PARTY_LICENSES.md` — verbatim license texts for Sparkle, SwiftTerm, GhosttyKit / libghostty, Muxy
- `RELEASE-CHECKLIST.md` — human-driven items with explicit handoff notes

**Modify:**
- `README.md` — add quickstart/usage section, link to architecture doc, link to release checklist

---

## Task 1: THIRD_PARTY_LICENSES.md

**Files:**
- Create: `THIRD_PARTY_LICENSES.md`

- [ ] **Step 1: Compose the file**

Create `THIRD_PARTY_LICENSES.md` at the repo root:

```markdown
# Third-Party Licenses

Roost embeds and links the following third-party software. Each retains its original license; this file aggregates the texts for distribution.

## Muxy

Roost's Swift codebase is forked from [Muxy](https://github.com/muxy-app/muxy) and continues to track upstream as `vendor/muxy-main`.

License: MIT

```
MIT License

Copyright (c) 2026 Muxy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Sparkle

Roost uses [Sparkle](https://github.com/sparkle-project/Sparkle) for in-app updates.

License: MIT

```
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

(Sparkle also includes EXTERNAL_LICENSES for sub-components — those propagate transparently when Sparkle is embedded as an SPM dependency. Refer to https://github.com/sparkle-project/Sparkle for the up-to-date sub-component texts.)

## SwiftTerm

Roost may use [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) for terminal-related utility code.

License: MIT

```
MIT License

Copyright (c) 2019 Miguel de Icaza

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## libghostty / GhosttyKit

Roost embeds [libghostty](https://github.com/ghostty-org/ghostty) via the `GhosttyKit.xcframework` precompiled bundle. The xcframework is built from the [muxy-app/ghostty](https://github.com/muxy-app/ghostty) fork.

License: MIT (same as upstream Ghostty)

```
MIT License

Copyright (c) 2024 Mitchell Hashimoto

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
```

If any actual upstream copyright statement differs from the boilerplate above (e.g., Sparkle's specific contributor list), use the verbatim text from the upstream LICENSE file. The texts above are the standard MIT boilerplate; replace with upstream specifics if needed.

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(license): bundle third-party license attributions"
```

---

## Task 2: README updates

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Read existing README**

```bash
cat README.md
```

- [ ] **Step 2: Insert Quickstart + Architecture pointer**

After the existing "Local Development" section, insert two new sections (preserve existing content):

```markdown
## Quickstart

After `swift build`, launching Roost (`swift run Roost`) and opening a project gives you a sidebar with workspaces. Inside each project:

- Add a workspace: sidebar context menu → "New Workspace…"
- Open an agent tab: File → New Claude Code Tab / New Codex Tab / New Gemini CLI Tab / New OpenCode Tab
- View jj changes: ⌘K (Source Control) — current change card, file list, bookmarks, conflicts, mutating actions
- Session history: clock icon in sidebar footer

A jj-tracked project unlocks the full jj-first behaviour. Git-tracked projects continue to work via the legacy panel.

## Configuration

Roost reads `<project>/.roost/config.json` for per-project settings. Schema version 1 supports:

- `setup`: list of `{ name?, command }` to run after creating a workspace
- `agentPresets`: list of `{ name, kind, command, cardinality }` overrides for built-in agents

Legacy `.muxy/worktree.json` is still read as a fallback for `setup` only.

## Architecture

See [docs/architecture.md](docs/architecture.md) and [docs/roost-migration-plan.md](docs/roost-migration-plan.md) for the full architecture and migration plan.

## Release Checklist

See [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) for the manual handoff items (signing, notarization, telemetry, distribution).

## Third-Party Licenses

See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for attribution of dependencies.
```

If the README's existing structure conflicts with this, prefer additive edits — keep all existing sections, append the new ones at the bottom (above the License heading) or merge sensibly with the existing flow.

- [ ] **Step 3: Commit**

```bash
jj commit -m "docs(readme): add quickstart, configuration, release checklist links"
```

---

## Task 3: RELEASE-CHECKLIST.md

**Files:**
- Create: `RELEASE-CHECKLIST.md`

- [ ] **Step 1: Compose the file**

Create `RELEASE-CHECKLIST.md` at the repo root:

```markdown
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
  - Build separate Xcode project (or extend with xcodegen) producing `.xpc` bundle.
  - Embed under `Roost.app/Contents/XPCServices/`.
  - NSXPCConnection client wraps existing `RoostHostdClient` protocol (the abstraction is already in place).
  - Sandbox + entitlement story for inter-process PTY ownership.

## Pre-Release Smoke

- [ ] `scripts/checks.sh` clean.
- [ ] Manual session lifecycle smoke:
  - Create + close project
  - Create + remove workspace
  - Open agent tab → exit Claude → re-launch from history
  - Open VCS panel on jj repo → describe / new / commit / squash / abandon
- [ ] Re-test on the lowest supported macOS version (14.0).
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(release): RELEASE-CHECKLIST.md for human-driven distribution items"
```

---

## Task 4: Final clean checks pass

**Files:**
- (verification only — no source edits expected)

- [ ] **Step 1: Run the full check suite**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
swiftformat --lint MuxyShared/Config/ Muxy/Services/Config/ Muxy/Services/Hostd/ Muxy/Views/Hostd/ 2>&1 | tail -5
```

If lint reports issues on Phase 7 / Phase 8 files, run `swiftformat MuxyShared/Config/ Muxy/Services/Config/` and commit any auto-fixes.

If tests fail or build breaks, surface the failure as a BLOCKED status — don't push through.

- [ ] **Step 2: Optional commit**

If swiftformat made auto-fixes:

```bash
jj commit -m "chore(format): auto-fix Phase 7/8 files"
```

Otherwise no commit.

---

## Task 5: Migration plan note

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Append at the bottom of Phase 8 section**

In the Phase 8 section, append:

```markdown
**Status (2026-04-28): Phase 8 (engineering subset) landed.**

- `THIRD_PARTY_LICENSES.md` bundles license texts for Muxy, Sparkle, SwiftTerm, libghostty.
- `README.md` adds Quickstart, Configuration, Architecture, Release Checklist, and Third-Party Licenses sections.
- `RELEASE-CHECKLIST.md` enumerates the human-driven release items: signing, notarization, Sparkle feed, Homebrew cask, telemetry, crash reporting, permissions audit, XPC service (deferred), pre-release smoke.
- **Phase 8 engineering work complete.** Distribution gates (Apple Developer Team ID, signing identity, notarization CI, app icon, Sparkle hosting, Homebrew cask submission) are tracked in `RELEASE-CHECKLIST.md` as human follow-up.
```

- [ ] **Step 2: Commit**

```bash
jj commit -m "docs(plan): mark Phase 8 (engineering subset) landed"
```

---

## Self-Review Checklist

- [ ] No code changes (this is a docs-only phase).
- [ ] All four documents created/updated and committed atomically.
- [ ] Build + test still green.
- [ ] Out-of-scope items explicitly enumerated in `RELEASE-CHECKLIST.md`.
