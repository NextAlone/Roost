# Documentation Audit Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring Roost's user-facing, architecture, migration, and historical planning documentation into a consistent current state after the Muxy upstream rebase and jj-first work.

**Architecture:** Treat root-level public docs and active runbooks as current product truth, while marking `docs/superpowers/*` as historical implementation artifacts. Keep Muxy references where they describe upstream lineage or intentionally retained source paths, and replace them where they incorrectly describe current product identity, commands, URLs, or release behavior.

**Tech Stack:** Markdown, Swift Package project docs, jj for VCS verification, shell-based grep scans with `rg`.

---

## File Structure

- Modify: `CLAUDE.md` — agent-facing project guide; should describe Roost, current commands, jj-first behavior, and current persistence paths.
- Modify: `CONTRIBUTING.md` — public contributor guide; should point to Roost setup and current run target.
- Modify: `SECURITY.md` — public vulnerability reporting policy; should avoid upstream Muxy reporting links unless explicitly marked upstream-only.
- Modify: `PRIVACY.md` — public privacy policy; should describe Roost desktop behavior, current remote/mobile status, agents, subprocesses, and local storage.
- Modify: `docs/architecture.md` — active architecture source of truth; should document Roost identity, jj panel, current URL scheme, current CLI decision, and remote server state.
- Modify: `docs/remote-server.md` — active API reference; should identify Roost, document `vcsKind`, jj workspace semantics, and legacy Git method naming.
- Modify: `docs/notification-setup.md` — active notification integration guide; should describe current socket/env names accurately and explain any legacy `MUXY_*` naming if retained.
- Modify: `docs/roost-migration-plan.md` — current migration ledger; should preserve unfinished goals, reclassify stale Outstanding entries, and replace unsafe jj commands.
- Modify: `docs/superpowers/README.md` — new directory note marking plans/specs as historical implementation artifacts, not current runbooks.
- Optional modify: `docs/superpowers/specs/2026-05-01-permissions-design.md` — add a short historical status note if the new directory README is not considered sufficient.
- Verify only: `README.md`, `RELEASE-CHECKLIST.md`, `docs/permissions.md`, `THIRD_PARTY_LICENSES.md`, `CODE_OF_CONDUCT.md`, `docs/building-ghostty.md` — likely acceptable after scan; update only if verification finds contradictions.

## Task 1: Establish Current Documentation Boundaries

**Files:**
- Create: `docs/superpowers/README.md`
- Modify: `README.md` only if adding an index link is wanted after review

- [ ] **Step 1: Create a historical-artifacts notice**

Create `docs/superpowers/README.md` with:

```markdown
# Superpowers Plans and Specs

This directory contains historical implementation plans and design specs used while building Roost.

These files are not current user documentation or active runbooks. They may include command examples, TODO-style checklists, intermediate design decisions, and references to Muxy names that were accurate when the plan was written.

For current Roost behavior, use:

- [README](../../README.md)
- [Architecture](../architecture.md)
- [Permissions](../permissions.md)
- [Release checklist](../../RELEASE-CHECKLIST.md)
- [Remote server API](../remote-server.md)
- [Notification setup](../notification-setup.md)
```

- [ ] **Step 2: Verify the historical note is discoverable**

Run:

```bash
test -f docs/superpowers/README.md && sed -n '1,80p' docs/superpowers/README.md
```

Expected: the file prints the notice and current-doc links.

- [ ] **Step 3: Scan historical docs without treating every TODO as release-blocking**

Run:

```bash
rg -n "TODO|TBD|Outstanding|swift run Muxy|muxy://" docs/superpowers
```

Expected: matches may remain in historical plans; they are acceptable once `docs/superpowers/README.md` marks the directory as historical.

- [ ] **Step 4: Record completion**

Use jj, not git:

```bash
jj st
jj commit -m "docs: mark superpowers plans historical"
```

Expected: one focused documentation change if the task is executed as its own change.

## Task 2: Rebrand Root Public Docs to Roost

**Files:**
- Modify: `CONTRIBUTING.md`
- Modify: `SECURITY.md`
- Modify: `PRIVACY.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update `CONTRIBUTING.md` identity and commands**

Replace the opening and setup sections so they point to Roost:

```markdown
# Contributing to Roost

Thank you for your interest in contributing to Roost. This guide covers the current Roost fork, which intentionally keeps several source directories named `Muxy/`, `MuxyShared/`, and `MuxyServer/` to reduce upstream merge conflicts.
```

Use current local development commands:

```bash
scripts/setup.sh
swift build
swift run Roost
```

Remove or rewrite the stale clone block that points to `https://github.com/muxy-app/muxy.git`. If a public Roost repository URL is not finalized, say:

```markdown
Clone the Roost repository URL used by the project maintainers, then run:
```

- [ ] **Step 2: Update `CONTRIBUTING.md` VCS language**

In “Development Workflow”, replace branch/fork wording with jj-compatible wording:

```markdown
1. Start from the current main change.
2. Make a focused change.
3. Run checks before describing or submitting the change:
```

Keep the existing check command:

```bash
scripts/checks.sh --fix
```

- [ ] **Step 3: Update `SECURITY.md` reporting target**

Replace Muxy-specific text with Roost:

```markdown
If you discover a security vulnerability in Roost, please report it responsibly.
```

If the Roost private advisory URL is not known, do not leave the Muxy advisory URL as the primary route. Use:

```markdown
Report vulnerabilities privately to the maintainers using the private channel listed by the Roost repository. Do not open a public issue for security vulnerabilities.
```

Keep this upstream carve-out:

```markdown
For vulnerabilities in libghostty, report them to the Ghostty project directly.
```

- [ ] **Step 4: Rewrite `PRIVACY.md` around current Roost behavior**

Replace the Muxy iPhone/iPad opening with:

```markdown
Roost is a macOS developer tool that hosts terminals, jj workspaces, coding-agent CLIs, optional local remote-server features, and local notification hooks.
```

The policy must explicitly cover:

- no Roost account
- no Roost telemetry or analytics in the current release
- project files stay local unless user-run commands or agents transmit data
- `.roost/config.json` may reference Keychain items
- in-app notifications may store truncated command/agent messages locally
- remote/mobile server is local-network only when enabled
- Sparkle is present but automatic updates are not the current release contract

- [ ] **Step 5: Rewrite `CLAUDE.md` as a Roost agent guide**

Update:

- title: `# Roost`
- run command: `swift run Roost`
- persistence: separate current legacy Muxy app-support storage from Roost config storage
- VCS: Roost is jj-first; Git panel remains legacy for Git projects
- agent/session concepts: Claude Code, Codex, Gemini CLI, OpenCode, terminal

Keep the existing “NSViewRepresentable Pitfalls” section if still true.

- [ ] **Step 6: Verify root docs no longer mislead**

Run:

```bash
rg -n "Contributing to Muxy|swift run Muxy|muxy-app/muxy/security|Muxy \\(\"the app\"\\)|Application Support/Muxy/projects.json" CLAUDE.md CONTRIBUTING.md SECURITY.md PRIVACY.md
```

Expected: no matches, except intentional upstream-attribution wording if added with context.

- [ ] **Step 7: Run checks**

Run:

```bash
scripts/checks.sh --fix
```

Expected: formatting, linting, build, and tests pass.

- [ ] **Step 8: Record completion**

```bash
jj st
jj commit -m "docs: update public guides for Roost"
```

## Task 3: Fix CLI and URL Scheme Documentation After Product Decision

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/notification-setup.md` only if socket/CLI wording depends on the decision
- Code synchronization included in this cleanup: `Muxy/Services/CLIAccessor.swift`, `Muxy/Resources/scripts/roost-cli`

- [ ] **Step 1: Confirm the product decision**

Decide one of these before editing active docs:

```text
Option A: Current release keeps the installed command named `muxy` for compatibility, but it must open `roost://` and `app.roost.mac`.
Option B: Current release renames the installed command to `roost`, with `muxy` kept only as a deprecated compatibility shim.
```

Recommended: Option B for user-facing release clarity, with a compatibility shim only if existing users need it.

- [ ] **Step 2: Update `docs/architecture.md` URL scheme section**

If Option B is chosen, the CLI section should say:

```markdown
- **`roost` shell wrapper** — resolves the argument to an absolute directory and tries, in order: open the `roost://open?path=<percent-encoded>` URL, fall back to `open -b app.roost.mac`, and finally pipe `open-project|<path>` to the notification socket.
- **`roost://` URL scheme** — handled by `AppDelegate.application(_:open:)`.
```

If Option A is chosen, explicitly call out:

```markdown
The command name remains `muxy` for compatibility, but it targets Roost's `roost://` URL scheme and `app.roost.mac` bundle identifier.
```

- [ ] **Step 3: Add a code follow-up note if docs expose current code breakage**

Because the previous code installed and ran `muxy` with the old Muxy URL and bundle identifiers, keep the implementation synchronized with the documented Roost CLI:

```markdown
Implementation synchronized: `Muxy/Resources/scripts/roost-cli` and `CLIAccessor.installCLI` target `roost`, `roost://`, and `app.roost.mac`.
```

Do not claim CLI docs are fixed unless the code and docs both target the same command, scheme, and bundle identifier.

- [ ] **Step 4: Verify active docs no longer advertise impossible URL behavior**

Run:

```bash
rg -n "muxy://|com\\.muxy\\.app|/usr/local/bin/muxy|Install Muxy CLI" docs/architecture.md docs/notification-setup.md README.md CONTRIBUTING.md
```

Expected:

- Option B: no matches.
- Option A: matches only where explicitly labeled compatibility command, and no `muxy://` / `com.muxy.app`.

- [ ] **Step 5: Record completion**

```bash
jj st
jj commit -m "docs: align CLI and URL scheme docs"
```

## Task 4: Update Active Architecture for jj-First Roost

**Files:**
- Modify: `docs/architecture.md`

- [ ] **Step 1: Update the document opening**

Replace the first paragraph with:

```markdown
Roost is a macOS terminal orchestrator built on the upstream Muxy SwiftUI + libghostty foundation. It keeps the upstream source directory names (`Muxy/`, `MuxyShared/`, `MuxyServer/`) to reduce merge conflicts, while adding jj-first workspace semantics, coding-agent sessions, and Roost configuration.
```

- [ ] **Step 2: Update hierarchy section**

Change the hierarchy description to explain:

- `Project -> Worktree` remains the compatibility UI/data model
- Git projects use Git worktrees and legacy Git VCS panel
- jj projects map `Worktree` slots to jj workspaces
- `vcsKind` distinguishes Git and jj behavior

- [ ] **Step 3: Update persistence section**

Keep legacy `MuxyFileStorage` paths only if they are still code reality, but label them as legacy app-state paths. Keep Roost paths for:

- `~/Library/Application Support/Roost/config.json`
- project `.roost/config.json`
- `~/Library/Application Support/Roost/hostd/sessions.sqlite`

Avoid the blanket sentence “All files in `~/Library/Application Support/Muxy/`” because Roost now has split storage.

- [ ] **Step 4: Split VCS section into Git and jj paths**

Replace “VCS Tab Layout” with two subsections:

```markdown
## Source Control

`VCSTabState` detects `VcsKind` for the active project. Git projects use the legacy Git panel. jj projects lazy-create `JjPanelState` and render `JjPanelView`.

### Git Panel

...

### jj Changes Panel

`JjPanelLoader` composes status, current change summary, diff summary, bookmarks, and conflicts. `JjPanelView` renders the current change card, file list, bookmark list, conflict list, and action controls. Mutating actions serialize through `JjProcessQueue.shared`.
```

Mention current jj actions:

- describe
- new
- commit
- squash
- abandon
- duplicate
- backout
- bookmark create/delete/move

- [ ] **Step 5: Update remote server architecture note**

In the Remote Server section, describe it as a Roost-embedded `MuxyRemoteServer` library, not “inside Muxy.app”. Keep `MuxyShared` names as source module names.

- [ ] **Step 6: Verify `architecture.md` has current jj references**

Run:

```bash
rg -n "JjPanelState|JjPanelView|JjPanelLoader|VcsKind|bookmark|roost://" docs/architecture.md
```

Expected: matches for all key jj/current Roost terms.

- [ ] **Step 7: Scan for stale active-architecture terms**

Run:

```bash
rg -n "Muxy is a macOS|inside Muxy\\.app|muxy://|com\\.muxy\\.app|All files in `~/Library/Application Support/Muxy/`" docs/architecture.md
```

Expected: no matches.

- [ ] **Step 8: Record completion**

```bash
scripts/checks.sh --fix
jj st
jj commit -m "docs: refresh architecture for jj-first Roost"
```

## Task 5: Update Remote Server API Reference

**Files:**
- Modify: `docs/remote-server.md`

- [ ] **Step 1: Rebrand API overview**

Change opening lines to:

```markdown
Roost exposes a WebSocket API that lets external clients connect to the desktop app over the local network when the remote server is enabled.
```

Replace “Muxy’s Mobile settings” with current Settings wording. If the UI still says “Mobile”, write:

```markdown
The setting currently lives under Settings -> Mobile because the remote-server module is inherited from Muxy.
```

- [ ] **Step 2: Document `vcsKind` in Worktree object**

Update Worktree example:

```json
{
  "id": "uuid",
  "name": "main",
  "path": "/Users/example/project",
  "branch": "main",
  "isPrimary": true,
  "canBeRemoved": false,
  "createdAt": "2026-04-19T10:00:00Z",
  "vcsKind": "jj"
}
```

Add:

```markdown
`vcsKind` is `git` or `jj`. For jj workspaces, legacy field names such as `branch` and `vcsAddWorktree` are compatibility names; the value represents bookmark/ref input where applicable.
```

- [ ] **Step 3: Rename API section heading without breaking method names**

Change:

```markdown
### Git and Worktrees
```

to:

```markdown
### VCS and Workspaces
```

Add:

```markdown
Method names retain legacy `vcs*` and `Worktree` terminology for protocol compatibility. Behavior is selected from the project's `vcsKind`.
```

- [ ] **Step 4: Document jj behavior for `vcsAddWorktree`**

Add under the method table:

```markdown
For jj projects, `vcsAddWorktree` creates a jj workspace at Roost's resolved workspace location. `name` becomes the workspace name, `branch` is treated as the target bookmark/ref input, and `createBranch` maps to creating the ref when supported by the selected controller.
```

- [ ] **Step 5: Verify DTO parity**

Run:

```bash
rg -n "vcsKind|VCS and Workspaces|legacy.*Worktree|Roost exposes" docs/remote-server.md
```

Expected: all terms are present.

- [ ] **Step 6: Record completion**

```bash
jj st
jj commit -m "docs: update remote API for Roost VCS kinds"
```

## Task 6: Update Notification Setup Guide

**Files:**
- Modify: `docs/notification-setup.md`

- [ ] **Step 1: Rebrand product text**

Replace Muxy product references with Roost:

```markdown
Roost ships built-in integrations for Claude Code, Codex, Cursor, and OpenCode where supported by the provider integration registry.
```

Before claiming provider list, verify code:

```bash
rg -n "AgentKind|Provider|hookScriptName|hasNotificationIntegration" Muxy/Services MuxyShared/Agent
```

- [ ] **Step 2: Keep legacy env names but explain them**

Because code currently exports `MUXY_SOCKET_PATH` and `MUXY_PANE_ID`, document them as current legacy-compatible names:

```markdown
Roost currently exports the socket path as `MUXY_SOCKET_PATH` and the pane identifier as `MUXY_PANE_ID` for compatibility with inherited Muxy hook scripts. Treat these names as the current integration contract until a `ROOST_*` compatibility layer lands.
```

- [ ] **Step 3: Verify socket path truth**

Check code:

```bash
sed -n '1,40p' Muxy/Services/NotificationSocketServer.swift
sed -n '210,230p' Muxy/Views/Terminal/TerminalPane.swift
```

Expected: socket path and env var names match the documentation.

- [ ] **Step 4: Update examples names without changing env vars**

Rename helper functions from `muxy_notify` to `roost_notify`, while still reading current env vars:

```bash
roost_notify() {
    [ -z "${MUXY_SOCKET_PATH:-}" ] && return 0
    local title="${1:-Done}"
    local body="${2:-}"
    local safe_body
    safe_body=$(printf '%s' "$body" | tr '|\n\r' '   ' | head -c 500)
    printf '%s|%s|%s|%s' "custom" "${MUXY_PANE_ID:-}" "$title" "$safe_body" \
        | nc -U "$MUXY_SOCKET_PATH" 2>/dev/null || true
}
```

- [ ] **Step 5: Verify stale notification wording**

Run:

```bash
rg -n "How Muxy Receives|sending notifications into Muxy|From anywhere inside a Muxy|Muxy respects" docs/notification-setup.md
```

Expected: no matches.

- [ ] **Step 6: Record completion**

```bash
jj st
jj commit -m "docs: update notification setup for Roost"
```

## Task 7: Clean Migration Plan Ledger

**Files:**
- Modify: `docs/roost-migration-plan.md`

- [ ] **Step 1: Classify entries before editing**

Do not delete migration-plan content just because it is old. Classify every questionable line into one of these buckets:

```markdown
- Current invariant: still constrains the architecture or workflow.
- Completed ledger: already landed and should remain as implementation history.
- Active backlog: still a target or known missing capability.
- Historical note: once true, now superseded by a later status entry.
- Stale command/example: must be replaced because following it would be wrong.
```

Use this command to find the high-risk lines:

```bash
rg -n "Outstanding|upcoming|deferred|Future enhancements|Later features|Still deferred|jj rebase -r|Risk Register|Goal:|Tasks:" docs/roost-migration-plan.md
```

Expected active backlog items to preserve include, at minimum:

- Phase 2 path-based external jj workspace import remains limited by jj workspace path exposure.
- Phase 4 `idle` / `errored` lifecycle states remain deferred unless new Ghostty lifecycle hooks exist.
- Phase 5 future enhancements: per-action revset pickers, push/pull bookmarks, rename bookmark, conflict resolution UI, DAG view, op log / undo.
- Phase 6 real cross-process XPC hostd remains a separate infrastructure task.
- Phase 8 future distribution work: Developer ID notarization, Sparkle appcast hosting, Homebrew cask distribution, telemetry decision, crash reporting, and real XPC hostd release posture.
- Risk Register entries remain product constraints unless explicitly mitigated elsewhere.

- [ ] **Step 2: Replace unsafe upstream merge command**

Change:

```bash
jj rebase -r @ -d vendor/muxy-main
```

to:

```bash
jj git fetch --remote muxy-upstream
jj bookmark set vendor/muxy-main -r main@muxy-upstream
jj new main
jj rebase -b @ -d vendor/muxy-main
swift build
```

Add:

```markdown
Use `-b @` for the current integration stack. Do not use `jj rebase -r <rev>` for upstream integration changes because it can move only one revision and leave descendants behind.
```

- [ ] **Step 3: Reclassify stale Outstanding entries without deleting goals**

At the Phase 1/2 boundary, replace stale lines about unresolved migration and failing `MuxyURLOpenTests` with:

```markdown
Historical note: these items were open before Phase 2 started. They were resolved by the Phase 2 cleanup batch below, including the `muxy://` -> `roost://` URL test fallout and jj executable discovery cleanup.
```

Only use this treatment for items with a later landed status proving resolution. Keep true future goals under an explicit `Active backlog` or `Future work` heading.

- [ ] **Step 4: Normalize completed/deferred lines in Phase 7**

The Phase 7 section has multiple “Still deferred” lines that were later resolved. Keep the chronology, but add one final status sentence:

```markdown
Current status after follow-ups: config write path, chmod enforcement, teardown, notifications config, and settings UI have landed. Earlier “Still deferred” bullets are preserved as historical phase notes, not active backlog.
```

- [ ] **Step 5: Preserve future goals in an explicit backlog**

Near the end of the migration plan, add or maintain a short future-work summary:

```markdown
## Active Backlog After Current Landed Phases

- jj changes: push/pull bookmarks, rename bookmark, conflict resolution UI, DAG view, op log / undo, and optional per-action revset pickers.
- sessions: richer lifecycle states beyond running/exited when reliable terminal lifecycle signals exist.
- hostd: real cross-process XPC service extraction with signing, sandbox, PTY ownership, and attach/release protocol.
- release: Developer ID notarization, Sparkle appcast hosting, Homebrew distribution, crash reporting/log export, and any future telemetry only after separate opt-in design.
- upstream integration: keep Muxy lineage mergeable and avoid large source-directory renames until the upstream strategy changes.
```

- [ ] **Step 6: Verify migration plan no longer instructs banned command**

Run:

```bash
rg -n "jj rebase -r|MuxyURLOpenTests.*fail|Outstanding before Phase 2" docs/roost-migration-plan.md
```

Expected: no matches for `jj rebase -r`; stale failure and Outstanding wording only appears if explicitly marked historical.

- [ ] **Step 7: Verify future goals were not lost**

Run:

```bash
rg -n "Active Backlog|push/pull bookmarks|rename bookmark|conflict resolution UI|DAG view|op log|XPC service|Developer ID|Sparkle appcast|Homebrew|Risk Register" docs/roost-migration-plan.md
```

Expected: each unfinished or future target still appears in the migration plan.

- [ ] **Step 8: Record completion**

```bash
jj st
jj commit -m "docs: clean migration plan status"
```

## Task 8: Final Cross-Document Consistency Pass

**Files:**
- Verify all Markdown files
- Modify any active doc found inconsistent

- [ ] **Step 1: Count and list docs**

Run:

```bash
rg --files -g '*.md' | sort
rg --files -g '*.md' | wc -l
rg --files -g '*.md' | xargs wc -l | tail -1
```

Expected: list includes root docs, `docs/*.md`, and historical `docs/superpowers/*`.

- [ ] **Step 2: Scan high-risk stale terms**

Run:

```bash
rg -n "swift run Muxy|Contributing to Muxy|Muxy \\(\"the app\"\\)|muxy-app/muxy/security|jj rebase -r|muxy://|com\\.muxy\\.app" -g '*.md'
```

Expected:

- No matches in active docs.
- Historical matches only under `docs/superpowers/plans` and only acceptable because `docs/superpowers/README.md` marks them historical.

- [ ] **Step 3: Scan Roost current-doc coverage**

Run:

```bash
rg -n "Roost|JjPanel|vcsKind|roost://|self-signed|SHA256SUMS|Application Support/Roost" README.md RELEASE-CHECKLIST.md docs/architecture.md docs/remote-server.md docs/notification-setup.md docs/permissions.md
```

Expected: each active doc has current Roost terminology appropriate to its scope.

- [ ] **Step 4: Run full checks**

Run:

```bash
scripts/checks.sh --fix
```

Expected: the script completes successfully.

- [ ] **Step 5: Review docs diff**

Run:

```bash
jj diff --git
```

Expected: diff is documentation-only unless Task 3's code follow-up was intentionally included in a separate implementation plan.

- [ ] **Step 6: Final status**

Run:

```bash
jj st
```

Expected: either clean after focused commits, or one active documentation change ready to describe.

## Open Decisions

1. CLI product name: `roost` only, or `muxy` compatibility command plus Roost URL/bundle target.
2. Security reporting URL: final Roost private advisory URL or maintainer private contact.
3. Privacy scope: whether current public policy should mention the inherited iOS/mobile app as supported, experimental, or not part of the current Roost release.
4. Whether to update historical plan files in place beyond adding `docs/superpowers/README.md`.

## Final Verification Checklist

- [ ] Root public docs identify Roost, not Muxy.
- [ ] Active docs do not point users to upstream Muxy commands, security reporting, or URL schemes.
- [ ] `architecture.md` documents jj-first source control and current Roost config/storage paths.
- [ ] `remote-server.md` documents `vcsKind` and legacy method naming.
- [ ] `notification-setup.md` matches actual env var and socket behavior.
- [ ] `roost-migration-plan.md` does not recommend `jj rebase -r`.
- [ ] Historical implementation plans are clearly marked historical.
- [ ] `scripts/checks.sh --fix` passes.
