# Roost Migration Plan

Roost is being rebuilt on top of Muxy. Muxy remains the upstream UI and terminal baseline; Roost adds jj-first workspace semantics and multi-agent orchestration.

## Baseline

- Roost `main` is based on `muxy-upstream/main`.
- `vendor/muxy-main` is a **jj bookmark** tracking imported upstream Muxy. It is not a disk path. `vendor/` on disk is `.gitignore`d for legacy Roost Rust artifacts (`GhosttyKit.xcframework` is the only allowed entry).
- The old Roost implementation is preserved in `old`, `feat-m6`, and `roost-rebuild`.
- The current directory names (`Muxy/`, `MuxyShared/`, `MuxyServer/`) are intentionally kept to reduce upstream merge conflicts.

## Reference Repositories

- Muxy: `https://github.com/muxy-app/muxy`
- Roost old line: local `feat-m6`
- Superset jj fork: local `/Volumes/Repository/MacOS/superset`
- Superset upstream: `https://github.com/superset-sh/superset`
- Agent Deck: `https://github.com/asheshgoplani/agent-deck`
- jj: `https://github.com/jj-vcs/jj`

Pin a known-good commit for each external repo before referencing source files in any phase doc; jj and Superset both move quickly enough that file paths rot within weeks.

## Product Positioning

Roost is a macOS-native, jj-first terminal orchestrator for coding agents.

Muxy already provides the hard native terminal foundation: SwiftUI, libghostty, split panes, tabs, themes, persistence, settings, VCS UI, and remote server primitives. Roost should preserve that foundation and replace the Git-first worktree layer with jj-first agent workspaces.

The target hierarchy is:

```text
Project -> jj Workspace -> Agent Session -> Terminal Pane
```

## Upstream Merge Policy

Keep Roost close enough to Muxy that upstream fixes can still be merged.

- Do not rename top-level upstream directories early.
- Do not delete upstream modules unless they block Roost.
- Prefer additive Roost code in new files and small adapters around upstream types.
- Keep `vendor/muxy-main` as the clean upstream tracking bookmark.
- Use a temporary integration branch/workspace for each upstream merge.
- Merge upstream terminal/libghostty/build fixes before large Roost feature branches.
- Document every deliberate fork point in this file or follow-up design docs.

Recommended flow:

```bash
jj git fetch --remote muxy-upstream
jj bookmark set vendor/muxy-main -r main@muxy-upstream
jj new main
jj rebase -r @ -d vendor/muxy-main
swift build
```

Use the exact revset appropriate to the active integration change; do not run destructive resets.

## Phase 0: Baseline Stabilization

Goal: keep the Muxy-based Roost mainline buildable and lock the contracts that every later phase depends on.

Tasks:

- Keep `swift build` green.
- Keep `scripts/setup.sh` working for `GhosttyKit.xcframework`.
- Preserve Muxy MIT license and attribution.
- Keep `.gitignore` protecting legacy Roost build artifacts such as `/target`, `/apps`, `/crates`, `/pocs`, `/vendor`, and `/.worktrees`.
- Avoid large directory renames until jj and agent layers are stable.
- Update README only with Roost-specific direction, not exhaustive product docs.
- Declare and CI-enforce the minimum jj version (target ≥ 0.20). jj is sub-1.0; CLI output and command names (e.g. `branch` → `bookmark`) shift between versions and any parser must assume version-pinned input.
- Wire `scripts/checks.sh` (formatting + lint + build) into the per-phase exit gate, not just per-task.
- Establish Swift 6 strict-concurrency posture for new modules: jj subprocesses are blocking, so all new services must be `actor`s or `Sendable` async APIs and must never be called on the main actor.
- Version `projects.json` (and any other persisted Roost state) with a `schemaVersion` field before Phase 2 starts mutating it. Old git-only `Worktree` records must round-trip through a documented migration when jj support lands.
- Add an "abort criteria" line to each phase doc as it lands (a simple stop-condition, e.g. "if Phase X does not converge within 2 weeks of dogfooding, retreat to git path"). No flag system required; the trigger is what matters.

Exit criteria:

- Working copy is clean **except for in-progress migration docs**.
- `swift build` passes.
- `scripts/checks.sh` passes.
- `main` points at the Roost baseline commit.
- `vendor/muxy-main` (jj bookmark) points at upstream Muxy.
- `projects.json` schema version is set; migration policy for unknown future versions documented.

## Phase 1: jj Service Layer

Goal: add a jj-native service without disturbing Muxy's UI too much.

Add:

- `JjProcessRunner` (actor; owns environment hygiene + cancellation)
- `JjRepositoryService`
- `JjWorkspaceService`
- `JjStatusParser`
- `JjDiffParser`
- `JjOpLogParser`
- `JjModels`

Initial commands:

- `jj root`
- `jj workspace list`
- `jj workspace add`
- `jj workspace forget`
- `jj log -r @ --no-graph -T '<template>'`
- `jj show -r <rev> --no-pager`
- `jj status --color=never --ignore-working-copy`
- `jj diff --summary`
- `jj diff --stat`
- `jj bookmark list`
- `jj bookmark create`
- `jj bookmark forget`
- `jj op log --no-graph -T '<template>' --ignore-working-copy` (status push source; see Phase 4)
- `jj resolve --list` (conflict enumeration)
- All read commands must support an `--at-op <op-id>` parameter for snapshot-isolated reads (see Snapshot policy).

Snapshot policy (mandatory — jj working copy is a commit):

- Every read-only call defaults to `--ignore-working-copy`. UI polling that does not need fresh snapshots **must not** trigger one. An accidental `jj status` from the UI mid-write captures whatever state the agent left on disk into the current change.
- Explicit snapshots happen only on user actions (Save, Commit, New Change, switch workspace).
- Service APIs expose snapshot-vs-no-snapshot as an explicit parameter; never an implicit side effect.
- Status views read at a pinned `--at-op` when available so concurrent agent work does not race the UI.

Subprocess environment contract (every jj invocation):

- `LANG=C.UTF-8`, `LC_ALL=C.UTF-8`, `NO_COLOR=1`
- `--no-pager`, `--color=never`, `--no-graph` for any command that supports them
- Explicit `PATH` (do not inherit shell PATH; avoids version managers / shims pointing at the wrong jj)
- Close stdin immediately (`Pipe()` + close) to prevent hangs when jj falls back to interactive prompts
- Strip `JJ_*` env vars except an explicitly injected `JJ_CONFIG`
- `HOME` from current user; never inherit a GUI tty

Concurrency model:

- `JjProcessRunner` is an actor; all subprocess calls are `async throws`.
- Streaming output uses `AsyncStream<Data>` so SwiftUI never blocks.
- Cancellation: `Task.cancel()` propagates to `Process.terminate()` (then SIGKILL after a short grace).
- Mutating-command allowlist (serialized per repo): `new`, `commit`, `squash`, `abandon`, `rebase`, `describe`, `bookmark set`, `bookmark create`, `bookmark forget`, `git push`, `git fetch`, `op restore`, `workspace add`, `workspace forget`. Read commands run concurrently.
- Cross-process reality check: agents in terminal panes invoke `jj` from outside Roost. Roost's per-repo serialization does **not** cover them; only jj's own store lock does. Document this assumption explicitly so Phase 4 status push is built on fs-watch (see Phase 4), not in-process state.

Testing:

- Parsers are fixture-driven. Check fixture jj repos (or recorded CLI output) into `Tests/Fixtures/`. Do not depend on a live jj at test time.
- CI runs the parser suite against a version matrix (minimum supported + latest) so jj upgrades surface as test failures, not runtime breakage.

Source references:

- Old Roost: `crates/roost-core/src/jj.rs`
- Superset fork: `apps/desktop/src/lib/trpc/routers/workspaces/utils/vcs/jj-provider.ts`
- Superset fork: `apps/desktop/src/lib/trpc/routers/changes/jj-*.ts`

Foundation status (as of 2026-04-27):

- Service-layer foundation landed via plan `docs/superpowers/plans/2026-04-27-jj-service-layer-foundation.md`. 11 commits add `JjProcessRunner` (env + args + subprocess), `JjProcessQueue` actor, `JjVersion`, parsers (`JjStatusParser`, `JjOpLogParser`, `JjConflictParser`, `JjWorkspaceParser`), and service shells (`JjRepositoryService`, `JjWorkspaceService`) plus a gated live-jj integration smoke. New Jj suite: 29 tests across 10 suites, all green.
- Phase 1 services landed (2026-04-27): `JjBookmarkParser`/`Service`, `JjDiffParser`/`Service` (`--stat` + `--summary`), `JjRepositoryService.show`, `JjShowParser`. Refactor pass: `JjProcessQueue.run` is throwing-generic, `JjRunFn` lives in `JjProcessRunner.swift`, all service-layer types narrowed to internal. Plan: `docs/superpowers/plans/2026-04-27-jj-cleanup-and-bookmark-diff-services.md`. Jj suite: 57 tests across 16 suites, all green.
- Outstanding before Phase 2 worktree adapter: data-migration plan for `projects.json`, Worktree field-mapping decisions (see Phase 2 spec).
- Outstanding cleanup tracked separately (not blocking Phase 2):
  - `JjProcessRunner.resolveExecutable` only searches `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`. Nix-profile users (`/etc/profiles/...`) need an env-driven extension.
  - 5 `MuxyURLOpenTests` cases (`muxy://...` URL parsing) fail at runtime because `AppDelegate.resolveProjectPath` was rebranded to expect `roost://` but tests still use `muxy://`. Pre-existing legacy fallout from the upstream Muxy → Roost rename; orthogonal to jj work.

## Phase 2: Worktree to jj Workspace Adapter

Goal: map Muxy's Worktree layer onto jj workspaces with minimal UI churn.

Approach:

- Keep `Worktree` as the compatibility UI model initially.
- Add a `vcsKind` or equivalent capability flag for `git` vs `jj`.
- For jj projects, treat `Worktree.path` as the jj workspace path.
- Replace `GitWorktreeService` calls behind creation/removal with `JjWorkspaceService`.
- Keep `WorktreeKey(projectID, worktreeID)` unchanged until the UI model is stable.

Field mapping (jj mode — must be decided before code changes start):

| Existing field | jj-mode meaning |
|----------------|-----------------|
| `branch: String?` | Current bookmark name (nullable; jj can have no bookmark on `@`). Add `currentChangeId: String?` separately for change identity. |
| `ownsBranch: Bool` | Repurpose as "create a bookmark when adding this workspace" (default false; jj does not require bookmarks). |
| `isPrimary: Bool` | True iff `workspace.name == "default"` and path is the repo root. Computed from jj, not stored. |
| `source: .external` | Already supported; Phase 2 must implement the import path for pre-existing jj workspaces (`jj workspace list` discovery). |

Do not:

- Rename `Worktree` to `JjWorkspace` in the first pass.
- Rewrite the sidebar reducer before command behavior is proven.
- Remove Git support until jj paths are working in daily use.

Data migration:

- Bump `projects.json` schema version (see Phase 0). Document explicitly: how does an existing git-only `Worktree` row behave when the user later adds a jj repo? Conversion, dual-mode, or rejection — pick one and write the migration test before changing the decoder.

Exit criteria:

- Open a jj repo as a project.
- List existing jj workspaces (including externally created ones).
- Create a new jj workspace from the sidebar.
- Switch active workspace.
- Persist and restore active workspace selection.
- `projects.json` migration round-trips a representative pre-jj fixture.

Phase 2.1 status (2026-04-27):

- `VcsKind` enum (`.git` default) added. `Worktree` extended with `vcsKind: VcsKind` + `currentChangeId: String?`; tolerant `decodeIfPresent` keeps v1 payloads loading as `.git`. Plan: `docs/superpowers/plans/2026-04-27-phase2-1-vcskind-and-projects-migration.md`.
- `projects.json` now wraps in `{ "schemaVersion": 2, "projects": [...] }`. Reader tolerates v1 bare arrays and unknown future versions; writer always emits v2. End-to-end round-trip integration test covers v1 fixture → v2 envelope.
- `VcsKindDetector` probes `.jj` then `.git` on disk; `WorktreeStore.makePrimary` stamps the result on each project's primary `Worktree`.
- Phase 2.2 (routing) remains: dispatch `WorktreeStore.refresh` and `RemoteServerDelegate.vcsCreateWorktree` by `vcsKind`, surface jj workspaces in the sidebar, and update `WorktreeDTO` IPC for mobile awareness.

Phase 2.2a status (2026-04-27):

- `WorktreeStore.refresh(project:)` dispatches by primary `Worktree.vcsKind`. Git path retains existing `refreshFromGit` behavior; new `refreshJj` updates tracked Worktrees' `currentChangeId` from `jj workspace list` and prunes stale `.muxy` entries by name. Plan: `docs/superpowers/plans/2026-04-27-phase2-2a-worktree-refresh-dispatch.md`.
- `JjWorkspaceParser` now consumes a tab-separated template (`name\tchange_id`) — gives full 32-char change_id without bracket parsing.
- `WorktreeRefreshHelper` (single existing caller) routed through the dispatcher; no UI behavior change.
- External jj workspace path discovery deferred (Phase 2.2c).
- Phase 2.2b remains: dispatch worktree create/remove via a `VcsWorktreeController` protocol; `RemoteServerDelegate.vcsCreateWorktree` and `CreateWorktreeSheet` consume the controller.

Phase 2.2b status (2026-04-27):

- `VcsWorktreeController` protocol introduced (`addWorktree` / `removeWorktree` / `deleteRef`). `GitWorktreeController` adapts `GitWorktreeService.shared`; `JjWorktreeController` composes `JjWorkspaceService` + `JjBookmarkService` with closure-injected impls for unit testability. Plan: `docs/superpowers/plans/2026-04-27-phase2-2b-worktree-controller-cleanup.md`.
- `VcsWorktreeControllerFactory.controller(for: VcsKind)` selects the implementation.
- `WorktreeStore.cleanupOnDisk` (both overloads) routes through the factory: per-worktree uses `worktree.vcsKind`, project-level orphan sweep uses primary's `vcsKind`.
- Phase 2.2b2 remains: route `RemoteServerDelegate.vcsCreateWorktree`, `CreateWorktreeSheet`, and `VCSTabState.deleteBranch` through the controller (UI-layer DI work).

Phase 2.2b2 status (2026-04-27):

- `VcsWorktreeControllerResolver` value type added; default delegates to `VcsWorktreeControllerFactory`. SwiftUI exposes it via `EnvironmentValues.vcsWorktreeControllerResolver`. Plan: `docs/superpowers/plans/2026-04-27-phase2-2b2-resolver-injection.md`.
- `RemoteServerDelegate.vcsCreateWorktree` looks up the project's primary `VcsKind` and routes through the resolver. Init takes the resolver with `.default` fallback; `MuxyApp` construction unchanged (default value).
- `CreateWorktreeSheet` reads the resolver via `@Environment(\.vcsWorktreeControllerResolver)`, dispatches `addWorktree` by the project's primary `vcsKind`, and stamps that kind on the newly created `Worktree`.
- Phase 2.2c remains: `VCSTabState.deleteBranch` and read-side probes (`isGitRepository`, `hasUncommittedChanges`) need a broader VCS abstraction; sidebar UI badges + `WorktreeDTO` IPC update also pending.

Phase 2.2c1 status (2026-04-28):

- `VcsStatusProbe` protocol + `GitStatusProbe` + `JjStatusProbe` + factory + `VcsStatusProbeResolver` (with SwiftUI environment key) added. Mirrors the controller-resolver pattern from Phase 2.2b2. Plan: `docs/superpowers/plans/2026-04-28-phase2-2c1-vcs-status-probe.md`.
- `ExpandedProjectRow` + `WorktreePopover` route `hasUncommittedChanges` through the resolver, dispatching by `worktree.vcsKind`. Behavior unchanged for git worktrees; jj worktrees now get a real status probe (snapshot-isolated `jj status --ignore-working-copy`) instead of an always-stale git answer.
- Phase 2.2c2/3 remains: `isGitRepository` callers, `VCSTabState.deleteBranch`, sidebar UI badges, `WorktreeDTO` IPC.

Phase 2.2c2 status (2026-04-28):

- `VcsKindDetector.isVcsRepository(at:)` synchronous disk probe added (returns true iff `.jj` or `.git` present). Plan: `docs/superpowers/plans/2026-04-28-phase2-2c2-vcs-repo-probe.md`.
- `ExpandedProjectRow` and `ProjectRow` swap `await GitWorktreeService.shared.isGitRepository(...)` for the synchronous helper. The `isGitRepo` variable name kept (rename would cascade through `WorktreePopover` and `VCSTabState`); its semantic widens to "any recognized VCS repo".
- Slight semantic divergence: a path with broken-but-present `.git` previously returned false (per `git rev-parse`); now returns true. Acceptable for sidebar UI gating; full repo-validity is checked when actually invoking VCS commands.
- Phase 2.2c3 remains: `VCSTabState.deleteBranch` and the broader VCSTabState read-side abstraction.

Phase 2.2c3 status (2026-04-28):

- `VCSTabState.deleteLocalBranch` routes through `VcsWorktreeControllerResolver.default` after a `VcsKindDetector.detect` lookup on `projectPath`. The git path is unchanged; jj projects now route to `JjBookmarkService.forget` via the controller's `deleteRef`.
- VCSTabState's read-side (branch listing, commit log, status, PR view, etc.) remains git-only. Full abstraction is deferred — VCSTabState is 1170+ lines of git-coupled state where extracting a `VcsRepositoryView` protocol is its own multi-task plan. UI labels will continue saying "branch" even for jj's bookmarks until that abstraction lands.
- Phase 2.2d remains: `WorktreeDTO` mobile IPC carries `vcsKind`, sidebar gets visual jj badges, optional `branch` label refinement.

Phase 2.2d status (2026-04-28):

- `VcsKind` relocated from `Muxy/Models/` to `MuxyShared/Vcs/` (now `public`); 6 Roost-target files added `import MuxyShared`. Plan: `docs/superpowers/plans/2026-04-28-phase2-2d-dto-vcskind-and-badge.md`.
- `WorktreeDTO` carries `vcsKind: VcsKind` with tolerant `decodeIfPresent` defaulting to `.git`; mobile clients on older builds still decode against newer payloads.
- `Worktree.toDTO` passes through. 3 round-trip tests added (toDTO / legacy decode / full encode-decode).
- `ExpandedProjectRow` worktree row shows a "JJ" capsule badge next to the name when `worktree.vcsKind == .jj` (mirrors the existing PRIMARY badge style).
- Outstanding: UI label refinement ("branch" → "bookmark" for jj), broader VCSTabState read-side abstraction.

Phase 2.2e status (2026-04-28):

- `VCSTabState` resolves and stores `vcsKind` at init via `VcsKindDetector.detect(at: projectPath)`. Plan: `docs/superpowers/plans/2026-04-28-phase2-2e-vcstabstate-vcskind-guard.md`.
- `performRefresh`, `loadBranches`, `loadCommits` early-return when `vcsKind != .git`. UI shows empty state for jj projects rather than spamming git errors.
- Mutating ops (commit/push/pull/etc.) intentionally not gated — their UI is reachable only after a successful read populates buttons; jj path leaves them dormant. Phase 5 jj Changes Panel will replace VCSTabState's read-side rather than extend it, so deeper abstraction here would be wasted effort.
- Phase 2 VCS adapter work effectively complete. Outstanding (Phase 5 territory): jj-native branches/commits/status/PR equivalents, conflict viewer, op log undo, dag view, "branch" → "bookmark" labels.

Phase 2 cleanup batch (2026-04-28):

- Pre-existing test fallout fixed: `MuxyURLOpenTests` 5 failures (`muxy://` → `roost://` URL strings); whole suite now 603/603 green.
- `JjIntegrationTests` gates on git binary in addition to jj (was implicit dep).
- `JjProcessRunner.resolveExecutable` extends to Nix profiles, `ROOST_JJ_PATH` env override, and `runRaw` supports cwd — `jj git init` integration smoke now actually executes on Nix-installed jj.
- `JjStatus.description` renamed to `workingCopySummary` for semantic clarity.
- `VCSTabState` mutating ops (push / pull / cherryPick / revert / createBranch / createTag / checkoutDetached / switchBranch / createAndSwitchBranch / pushSetUpstream + performGitOperation chokepoint) gated on `vcsKind == .git`.
- `CreateWorktreeSheet` labels switch between "Branch" / "Bookmark" based on the project's primary `VcsKind`.
- `WorktreeStore.refreshJj` now detects untracked external jj workspaces (names from `jj workspace list` not in tracked Worktree set) and surfaces via `untrackedJjWorkspaces(for:)`. `ExpandedProjectRow` shows an "N external jj workspaces detected" hint listing names. Path-based import binding deferred (jj's `WorkspaceRef` doesn't expose path).

Reviewer-driven cleanup (2026-04-28):

- 🔴 `JjProcessQueue.shared` singleton — fixes silent-broken per-repo serialization (default closures were each constructing fresh queues, so concurrent ops on same repo did not see each other's inflight task).
- 🔴 `Worktree.jjWorkspaceName: String?` field + `VcsWorktreeController.removeWorktree` gains explicit `identifier:` parameter. JjWorktreeController uses identifier when present; falls back to leaf-name heuristic only for orphan-sweep paths. Throws `JjWorktreeControllerError.workspaceNameNotFound` on miss instead of silent leak.
- 🔴 `GitDirectoryWatcher` renamed `VcsDirectoryWatcher`, supports `.jj` (watches `.jj/`, treats `/.jj/working_copy/`, `/.jj/repo/op_store/`, `/.jj/repo/index/` as noise). VCSTabState passes its kind; FileTreeState detects via VcsKindDetector. jj users now get FS-driven file-tree refresh.
- 🟡 `isGitRepo` renamed to `isVcsRepo` in 3 sidebar files (ExpandedProjectRow, ProjectRow, WorktreePopover param). VCSTabState retains git-only `isGitRepo` (truly git semantics).
- 🟡 `VCSTabView` shows "jj Changes Panel coming soon" placeholder when `state.vcsKind == .jj` instead of an empty broken-looking panel.
- 🟡 Untracked jj workspace hint becomes a Button: tap opens NSOpenPanel to bind a path; `WorktreeStore.importExternalJjWorkspace(name:path:into:)` creates the `Worktree(.external, vcsKind: .jj, jjWorkspaceName:)` record.

Deferred (acknowledged debt, not blocking):
- Full VCSTabState split (1170+ lines) and resolver consolidation (`VcsAdapter` aggregating controller + status probe + detector) — Phase 5 will replace VCSTabState's read-side, so deeper refactor here is wasted effort.
- jj output CI matrix (jj 0.40 / 0.41 / 0.42) — needs GitHub Actions wiring; opening as a tracked task.
- `VcsKind = .default` sentinel naming clarity.

External code-review pass (2026-04-28, codex):

- 🔴 `JjProcessQueue` keys on canonical repoPath (URL.standardizedFileURL.resolvingSymlinksInPath) so symlinks (/tmp ↔ /private/tmp), trailing slashes, and relative paths don't bypass per-repo serialization.
- 🔴 `WorktreeStore.importExternalJjWorkspace(name:path:into:)` now throws `ImportExternalJjWorkspaceError` for: pathDoesNotExist, pathNotJjWorkspace (no `.jj/` marker), duplicateName, duplicatePath. Sidebar surfaces an NSAlert.
- 🟡 `VcsDirectoryWatcher` resolves the metaPath canonically at init and uses prefix matching (not substring) — fixes the false-positive of nested user `.jj` dirs and the false-negative of jj internals outside the original 3-path filter (now: anything under `.jj/` is jj noise).
- 🟡 `VcsWorktreeController` protocol gets doc-comment spelling out per-VCS semantics for `force` (git: required for dirty; jj: ignored) and `identifier` (git: ignored; jj: workspace name).

Codex driven, but driven-back:
- "Old persisted jj worktrees lacking jjWorkspaceName need migration" — false alarm. The leaf-name fallback IS the migration path for legacy records (Roost-managed pre-Phase-2.2c worktrees have name == directory leaf, which matches what jj produced).
- "Shared queue self-deadlock" — audited; JjWorkspaceService / JjBookmarkService don't nest queued calls. No risk.

All known follow-ups landed (2026-04-28):
- Per-name "Bind…" button for each untracked jj workspace (codex UX iteration).
- `removeWorktree` tolerates already-deleted on-disk path after successful `jj workspace forget` (NSFileNoSuchFileError swallowed; other errors still throw).
- `VcsKind.default` static removed; all 9 callsites use `.git` explicitly. Future addition of `.unsupported` or third VCS won't silently piggyback the fallback.

Order-driven follow-up (2026-04-28):

- DECISION (#8): Phase 3 cardinality locked at N sessions : 1 workspace default; per-preset `requiresDedicatedWorkspace` for agents that need isolation. Forward-only; future migration would need data conversion.
- DECISION (#9): Phase 6 hostd implemented as Swift XPC service. Embedded Rust shelved (Hardened Runtime / notarization friction not worth reuse; the unique value-add is persistent PTYs which is new code regardless). Old `roost-hostd` Rust code (~5k LoC) kept as reference branch.
- CI: `.github/workflows/jj-integration.yml` runs gated integration smoke + parser-fixture tests against a pinned jj release (currently 0.40.0; matrix structure ready for 0.41/0.42/latest as they ship). Weekly cron catches output-format drift even without code changes.
- `VcsWorktreeRemovalTarget` enum (`.identified(String)` / `.orphan`) replaces `identifier: String?` — kills the codex-flagged footgun where `nil` was only safe for orphan-sweep callers. WorktreeStore call sites map `worktree.jjWorkspaceName` into the enum at call time.

## Phase 3: Agent Session Model

Goal: make terminal tabs agent-aware.

Add agent kinds:

- Terminal
- Claude Code
- Codex
- Gemini CLI
- OpenCode

Initial behavior:

- Agent sessions are terminal tabs with a preset command and workspace cwd.
- **DECISION (2026-04-28): Cardinality is N sessions : 1 workspace** (default). Multiple terminals can share one jj workspace; opening a coding-agent preset *suggests* a new workspace but does not force one. 1:1 is selectable per agent preset (e.g., Claude Code preset can default `cardinality: dedicated`).
  - Rationale: matches user mental model of "open another shell in the same project" while leaving room for agents that need isolation. Forced 1:1 would mean `jj workspace add` per shell — costs disk + cognitive overhead.
  - Implementation: `Session` model keys `(workspaceID, sessionID)`. Multiple sessions can share workspaceID. Per-preset boolean `requiresDedicatedWorkspace` triggers `jj workspace add` at session creation; otherwise reuse active workspace.
  - Data model is forward-only: future move to 1:1-default would require migration. Locked.
- Session metadata should include agent kind, workspace id/path, command, created time, and last known state.
- Existing Muxy notification hooks can remain, but Roost should expose agent status in its own model.

Reference ideas:

- Agent Deck: session grouping, status detection, search, MCP/skill management.
- Superset: workspace presets, agent monitoring, open-in-editor handoff.
- Old Roost: agent presets and `.roost/config.json` setup hooks.

Exit criteria:

- Create Terminal/Claude/Codex tabs from UI shortcuts.
- Agent tab cwd is the active jj workspace.
- Agent kind is visible in tab/session metadata.
- Session metadata survives app restart where possible.

**Status (2026-04-28): Phase 3 implementation landed.**

- AgentKind + AgentPreset live in MuxyShared (`MuxyShared/Agent/`).
- TerminalPaneState carries `agentKind` + `createdAt`. TerminalTabSnapshot persists both plus `startupCommand` (decode-tolerant — legacy snapshots default to `.terminal` / nil / now).
- `TabArea.createAgentTab(kind:)` + `AppState.createAgentTab(_:projectID:)` route the preset command into the active worktree path (cwd resolved automatically because `TabArea.projectPath` already stores the worktree path).
- Menu entries: New Claude Code / Codex / Gemini CLI / OpenCode Tab. ShortcutAction cases shipped with no default key bindings; users bind via Settings.
- `requiresDedicatedWorkspace` flag exists on `AgentPreset` but is **not enforced** (all built-ins default `false`); enforcement → Phase 4 sidebar work.
- "Last known state" lifecycle (running / idle / exited / errored) **deferred** to Phase 4 status badges.
- User-configurable presets / `.roost/config.json` integration → Phase 7.

## Phase 4: Roost Sidebar

Goal: move from Muxy's Project -> Worktree UI toward Roost's Project -> jj Workspace -> Session UI.

Plan:

- First, relabel UI language without changing model names internally.
- Then add a session list under each workspace.
- Keep Muxy's split pane/tab system for terminal layout.
- Add workspace status badges: clean, dirty, conflicted, running agents.
- Add agent state badges: running, waiting, idle, exited, errored.

Status push source:

- jj has no watch API. Use `DispatchSource` (or equivalent fs-watch) on `<repo>/.jj/repo/op_heads` as the change-of-state signal — this is the only cross-process notification path, since agents in panes invoke `jj` outside Roost.
- On op_heads change, query `jj op log -n 1 --no-graph -T '<id-template>' --ignore-working-copy` to learn the new op id, then refresh affected workspaces.
- Per-workspace dirty/conflict refresh runs `jj status --ignore-working-copy --at-op <op>` so polling never triggers an implicit snapshot (see Phase 1 snapshot policy).

Do not:

- Collapse split panes into a simple tab list.
- Remove Muxy's drag/drop or persistence behavior.
- Block jj work on full visual redesign.

Exit criteria:

- Sidebar can show all projects and jj workspaces.
- Active workspace and active session are clear.
- Dirty/conflict/running indicators update without manual app restart.

**Status (2026-04-28): Phase 4a (UI relabel) landed.**

- All user-facing "Worktree" / "worktree" strings rewritten to "Workspace" / "workspace" across sidebar (popover, project row, expanded row), creation sheet, refresh alert, global switcher overlay, settings, and File menu.
- Wholesale rename — no per-VcsKind branching. Roost is jj-first; "Workspace" is acceptable umbrella terminology for git projects.
- Internal type names (`Worktree`, `WorktreeStore`, `WorktreeKey`, `WorktreeDTO`, `WorktreeConfig`) and persistence (UserDefaults keys, `.muxy/worktree.json` config path) **kept** for backwards compatibility. Renaming model identifiers and migrating persistence is out of scope.
- ShortcutAction enum case `.switchWorktree` kept (stable keybinding identifier); only its `displayName` changed.
- Phase 4b (op_heads watcher + dirty/conflict badges), 4c (session list under workspace), 4d (`requiresDedicatedWorkspace` enforcement) → upcoming.

**Status (2026-04-28): Phase 4b (status watcher + badges) landed.**

- `WorkspaceStatus` enum (clean / dirty / conflicted / unknown) lives in `MuxyShared/Vcs/`.
- `VcsStatusProbe.status(at:)` extends the existing protocol; default implementation maps the legacy `hasUncommittedChanges` Bool to `.dirty`/`.clean`. Concrete probes override:
  - `JjStatusProbe.status` parses `jj status` (with `snapshot: .ignore`) for entries + `hasConflicts`. Conflicts dominate dirty.
  - `GitStatusProbe.status` parses `git status --porcelain=v1`; lines starting with `UU/AA/DD/AU/UA/UD/DU` mark conflicts.
- `WorkspaceStatusWatcher` is a new FSEventStream wrapper that does NOT filter `.jj/` events (purpose-built for status reactivity, separate from `VcsDirectoryWatcher` used by the diff panel).
- `WorkspaceStatusStore` (@Observable @MainActor) owns per-worktree watchers and `[UUID: WorkspaceStatus]`. Sidebar rows query via environment; `MainWindow.onChange(of: worktreeStore.worktrees, initial: true)` reconciles.
- Sidebar shows colored dot badges next to workspace names (no badge for `.clean`/`.unknown`; orange for dirty, red for conflicted).
- Phase 4c (session list under workspace) and Phase 4d (`requiresDedicatedWorkspace` enforcement) → upcoming.

**Status (2026-04-28): Phase 4c (session list) landed.**

- Sidebar workspace rows are now double-click expandable to reveal their sessions.
- Each session shows an SF Symbol icon per `AgentKind` (`terminal`, `sparkles`, `brain`, `star.circle`, `hammer`) plus the tab title.
- Clicking a session row activates that workspace and selects that tab via `appState.dispatch(.selectTab(...))`.
- `AppState.allTabs(forKey:)` flattens a workspace's tabs across split panes.
- Session lifecycle state (running / idle / exited / errored) **deferred** to a Phase 4c.5 follow-up (requires GhosttyTerminalNSView lifecycle hooks). Not blocking Phase 4d.
- Phase 4d (`requiresDedicatedWorkspace` enforcement) → upcoming.

**Status (2026-04-28): Phase 4c.5 (session lifecycle badge) landed.**

- `SessionLifecycleState` enum (running / exited) lives in `MuxyShared/Agent/`.
- `TerminalPaneState.lastState: SessionLifecycleState` defaults to `.running`. Volatile — not persisted to snapshot (lifecycle resets on restart since the process is gone).
- `TabAreaView.onProcessExit` now sets `pane.lastState = .exited` and conditionally force-closes the tab — only for non-agent panes (`agentKind == .terminal`). Agent panes stay visible with the exited badge so users can inspect output.
- `SessionRow` renders a small grey dot for `.exited` sessions; no badge for `.running` (default state, avoids clutter).
- `idle` and `errored` states deferred — no clean signal from Ghostty's current action wiring.

**Status (2026-04-28): Phase 4d (`requiresDedicatedWorkspace` enforcement) landed.**

- `ShortcutActionDispatcher.shouldRouteToWorkspaceCreation(kind:presetLookup:)` exposes the routing decision as a pure helper for testing.
- When `AgentPreset.requiresDedicatedWorkspace == true`, `performAgentTab` posts `.requestCreateWorkspaceForAgent` (carrying `kind.rawValue` in userInfo) instead of creating the tab in the active workspace.
- Sidebar rows (`ExpandedProjectRow`, `ProjectRow`) observe the notification, store `pendingAgentKind`, and present `CreateWorktreeSheet`. On successful workspace creation, the new workspace is activated and an agent tab of the pending kind is opened inside it.
- All built-in presets remain `requiresDedicatedWorkspace = false` — Phase 4d adds the routing scaffold without changing default UX. User-configurable presets land in Phase 7.
- **Phase 4 complete.** Phase 4c.5 (session lifecycle state badges) remains as an optional follow-up requiring GhosttyTerminalNSView lifecycle hooks.

## Phase 5: jj Changes Panel

Goal: replace Git-first VCS behavior with jj-first review behavior.

Minimum features:

- Current change id and description.
- Parent/current diff file list.
- Diff stat and summary.
- Bookmark list and current bookmark.
- Conflict list.
- Actions: describe, new, commit, squash, abandon, duplicate, backout, bookmark create/delete/move.

Later features:

- DAG view.
- Operation log / undo.

**Status (2026-04-28): Phase 5a (read-side panel) landed.**

- `JjPanelSnapshot` (value type), `JjPanelLoader` (composes `jj show @` + `jj status` + `jj diff --summary -r @-`), `JjPanelState` (@Observable @MainActor) live in `Muxy/Models` / `Muxy/Services/Jj`.
- `VCSTabState` lazy-owns `jjState: JjPanelState?` and dispatches `refresh()` by `vcsKind`.
- `JjPanelView` renders the change card (id + description), file list, conflict banner, and refresh button. Replaces the old `jjPlaceholder` (kept as fallback).
- Bookmarks (5b), conflicts detail (5b), and mutating actions (5c, 5d) → upcoming.

**Status (2026-04-28): Phase 5b (bookmarks + conflicts) landed.**

- `JjConflictsService` wraps `jj resolve --list` and uses existing `JjConflictParser`.
- `JjPanelSnapshot` adds `bookmarks: [JjBookmark]` + `conflicts: [JjConflict]`.
- `JjPanelLoader` lazily fetches conflicts only when `status.hasConflicts == true` (avoids extra subprocess in common case). Bookmarks always fetched.
- `JjPanelView` renders bookmark list (with target prefix + remote markers) and conflict list. The old conflict banner is removed.
- Mutating actions (5c, 5d) → upcoming.

**Status (2026-04-28): Phase 5c (mutating actions) landed.**

- `JjMutationService` exposes 7 mutations (describe, new, commit, squash, abandon, duplicate, backout) wrapping `jj <subcmd>` calls; all serialize through `JjProcessQueue.shared`.
- `JjActionBar` renders all 7 actions as a button bar above the change card.
- `JjMessageSheet` collects message input for describe + commit.
- After each successful mutation, `state.refresh()` reloads the panel.
- Errors surface inline below the action bar.
- Defaults: backout/abandon/duplicate operate on `@`; squash collapses `@` into `@-`. No per-action revset picker (deferred).
- Bookmark CRUD (5d) → upcoming.

**Status (2026-04-28): Phase 5d (bookmark CRUD) landed.**

- "+" button in the bookmarks section header opens `JjBookmarkCreateSheet` to create a bookmark targeting `@`.
- Right-click context menu on each bookmark row: "Move to current change" and "Delete" actions.
- All actions route through the existing `runMutation` helper for serialized execution + error surfacing + state refresh.
- **Phase 5 complete.** Future enhancements (deferred): per-action revset pickers, push/pull bookmarks, rename bookmark, conflict resolution UI, DAG view, op log / undo.
- Conflict content viewer.
- Revset search.
- Side-by-side diff improvements.

Rules:

- jj has no staging area; do not emulate Git staging as a first-class concept.
- The working copy is a commit; reflect that in language and actions.
- Bookmarks are not branches; avoid Git branch assumptions in UI text.

## Phase 6: Hostd and Session Persistence

Goal: selectively migrate the old Roost host daemon after the Muxy-based UI is stable.

Old Roost `feat-m6` provides:

- `roost-hostd`
- Unix socket JSON-RPC
- SQLite session history
- `roost-attach`
- PTY ownership in daemon
- shutdown release/stop modes
- live session restore

Implementation stack candidates:

1. **Swift rewrite + XPC service** — best macOS sandbox + entitlement story; loses old Rust code.
2. **Embed `roost-hostd` Rust binary + Unix socket** — reuses old code; needs group container entitlement and complicates notarization.
3. **Hybrid** — Swift wrapper, Rust core via FFI; highest implementation cost.

**DECISION (2026-04-28): Option 1 — Swift rewrite + XPC service.**

Rationale:
- Roost is macOS-native; XPC services + LaunchAgent + Apple sandbox model is the local idiom. Embedded Rust binaries fight Hardened Runtime and notarization.
- The reusable parts of `roost-hostd` (Unix socket JSON-RPC, SQLite history) are commodity reimplementation in Swift; the unique value is **persistent agent PTYs surviving app quit**, which is new behavior regardless of language.
- jj subprocess management is already in Swift (`JjProcessRunner`); duplicating subprocess control across two languages adds no leverage.
- XPC services get free `com.apple.security.app-sandbox` posture, codesign + notarize via standard archive flow, no separate ABI surface.
- Trade-off accepted: old `roost-hostd` Rust code (~5k LoC) is shelved as reference.

Implementation outline:
- `RoostHostdXPCService` — XPC service target in the app bundle (`Roost.app/Contents/XPCServices/RoostHostdXPCService.xpc`)
- Protocol: `@objc protocol RoostHostdProtocol` exposing `createSession`, `attachSession`, `listSessions`, `releaseSession`, `terminateSession`
- Storage: `~/Library/Application Support/Roost/hostd/sessions.sqlite` (per-user, sandboxed via app's container)
- PTY ownership: XPC service holds `posix_spawn`'d processes; client (main app) attaches via XPC handoff for stdout/stderr streams.
- Lifecycle: macOS auto-launches the XPC service on demand. Service stays alive while sessions are active; main app quitting releases its connection but session processes persist (XPC service maintains `dispatch_source` per pid).

Until Phase 6 starts, no hostd code; main app keeps direct PTY ownership.

Migration order:

- Keep direct Muxy/libghostty terminal spawning first.
- Add a protocol boundary for session creation.
- Introduce hostd behind a feature flag.
- Move long-running agent PTYs into hostd.
- Add attach/re-attach and session history UI.

Exit criteria:

- App can quit without killing released sessions.
- Relaunch can list and attach live sessions.
- Stop mode terminates sessions predictably.
- Stale manifest/socket cleanup is reliable.

**Status (2026-04-28): Phase 6a + 6b (in-process hostd foundation) landed.**

- `SessionRecord` DTO lives in `MuxyShared/Hostd/`. Persisted DTO with id / projectID / worktreeID / workspacePath / agentKind / command / createdAt / lastState.
- `SessionStore` actor wraps a single SQLite3 connection (`import SQLite3`, no SPM dep). Database at `~/Library/Application Support/Roost/hostd/sessions.sqlite`. Schema versioned via `PRAGMA user_version`.
- `RoostHostd` actor is the public API: `createSession`, `markExited`, `listLiveSessions`, `listAllSessions`, `deleteSession`, `pruneExited`. Injected into SwiftUI environment via `\.roostHostd` key.
- Agent tabs are recorded on creation via `AppState.createAgentTab(_:projectID:hostd:)` and marked exited via `TabAreaView.onProcessExit`.
- All sessions are still single-process — no XPC handoff yet. Sessions in the DB get marked `exited` if main app is killed (no graceful shutdown signal); Phase 6c needs to address.
- Phase 6c (XPC service extraction) and 6d (re-attach + history UI) → upcoming.

**Status (2026-04-28): Phase 6c + 6d (client abstraction + history UI) landed.**

- `RoostHostdClient` Swift protocol decouples call sites from the in-process actor. `LocalHostdClient` is the current implementation; future `XPCHostdClient` will wrap `NSXPCConnection` once an XPC service bundle is built (separate task — needs Xcode project surgery).
- All call sites (AppState.createAgentTab, ShortcutActionDispatcher, MuxyCommands, TabAreaView) now go through `(any RoostHostdClient)?` rather than the raw actor.
- On launch, `RoostHostd.markAllRunningExited()` flips any leftover `.running` records to `.exited` (in-process hostd implies process death == sessions dead). Real XPC will skip this.
- `SessionHistoryStore` (@Observable @MainActor) wraps client.listAllSessions; `SessionHistoryView` renders the recent 50 sessions with state badge + Re-launch + Prune Exited buttons.
- Re-launch opens a new agent tab in the same project + worktree (best-effort). Disabled if project / worktree no longer exists.
- Sidebar gains a clock-arrow button (in both collapsed + expanded footer layouts) that opens the history sheet.
- **Phase 6 in-process work complete.** Real cross-process XPC service is queued as a separate infrastructure task (Xcode project surgery + xcodebuild + codesign work).

## Phase 7: Roost Config and Presets

Goal: standardize project and agent automation.

Config files:

- `.roost/config.json`
- Future: user-level `~/Library/Application Support/Roost/config.json`

Initial fields (define a versioned JSON Schema before first read site lands):

- `schemaVersion: int`
- `setup: [{ name, command, cwd?, env? }]`
- `teardown: [{ name, command, cwd?, env? }]`
- `agentPresets: [{ name, kind, command, env?, cardinality: "shared" | "dedicated" }]`
- `defaultWorkspaceLocation: string`
- `env: { [key: string]: string | { fromKeychain: string } }`
- `notifications: { ... }`

Rules:

- Setup failures should warn but not block workspace creation by default.
- Commands run with an explicit cwd and shell.
- Secrets are referenced by Keychain item, not embedded inline. Plain values in `env` are allowed for non-sensitive config; never log env values.
- Config files have `chmod 600` enforced on first write; surface a warning if found wider.
- `.roost/` is excluded from jj/git tracking by default; document this in the project init flow.

**Status (2026-04-28): Phase 7 (config + presets) v1 landed.**

- `RoostConfig` (versioned, decode-tolerant) lives in `MuxyShared/Config/`. Schema version 1.
- `RoostConfigLoader.load(fromProjectPath:)` reads `.roost/config.json` first; falls back to legacy `.muxy/worktree.json` for the `setup` field only (back-compat).
- `AgentPresetCatalog.preset(for:configuredPresets:)` overload returns user overrides when a configured preset matches the requested `AgentKind`; otherwise built-in fallback. `cardinality: "dedicated"` maps to `requiresDedicatedWorkspace = true`.
- `TabArea.createAgentTab` now consults the loader at creation time — best-effort, falls back to built-ins on missing/invalid config.
- Out of scope this phase (deferred): `defaultWorkspaceLocation`, `teardown`, `env` resolution / Keychain references, `notifications` config, settings UI for editing config inline, `chmod 600` enforcement on writes (no write path exists yet). Schema reserves these keys but does not consume them.

**Follow-up status (2026-04-29): setup execution migrated.**

- `WorktreeSetupRunner` now reads setup commands through `RoostConfigLoader`, so `.roost/config.json` is the primary source and legacy `.muxy/worktree.json` remains a setup-only fallback.
- `CreateWorktreeSheet` previews the same normalized setup commands that execution uses and documents the `.roost/config.json` shape.

**Follow-up status (2026-04-29): plain env support landed.**

- `RoostConfig` decodes top-level `env`, per-setup `env`, and per-agent preset `env` plain string maps. Object values such as `{ "fromKeychain": "..." }` are tolerated but ignored until Keychain resolution lands.
- Setup execution merges top-level env with per-command env and prefixes each command with shell-escaped assignments.
- Agent tabs merge top-level env with per-preset env and pass the result to Ghostty when creating the terminal surface. Roost's own `MUXY_*` env vars still win.
- Still deferred: config write path / chmod enforcement and settings UI.

**Follow-up status (2026-04-29): default workspace location landed.**

- `RoostConfig.defaultWorkspaceLocation` controls where newly created workspaces are checked out. Absolute paths are used directly; relative paths resolve against the project root.
- `CreateWorktreeSheet` and remote `vcsAddWorktree` both use `WorkspaceLocationResolver`, so local and mobile/remote workspace creation share path semantics.
- Empty / missing location keeps the original Application Support checkout root.
- Still deferred: Keychain-backed env values, config write path / chmod enforcement, teardown, notifications config, and settings UI.

**Follow-up status (2026-04-29): Keychain-backed env support landed.**

- `env` values can be either plain strings or `{ "fromKeychain": "service", "account": "optional-account" }`.
- Setup commands and agent presets resolve Keychain references at launch time through macOS `/usr/bin/security`; unresolved entries are skipped and secret values are not persisted into config.
- Still deferred: config write path / chmod enforcement, teardown, notifications config, and settings UI.

**Follow-up status (2026-04-29): teardown support landed.**

- `RoostConfig.teardown` decodes the same command shape as `setup`, including `cwd` and env values.
- Managed worktree cleanup runs teardown commands before VCS removal. Commands execute with the worktree as default cwd; relative `cwd` values resolve under that worktree.
- Teardown failures are logged but do not block managed worktree cleanup.
- Still deferred: config write path / chmod enforcement, notifications config, and settings UI.

**Follow-up status (2026-04-29): notifications config landed.**

- `RoostConfig.notifications` supports `enabled`, `toastEnabled`, `sound`, and `toastPosition` as project-level overrides.
- `NotificationStore` applies global Settings defaults first, then project `.roost/config.json` overrides. `enabled: false` suppresses both saved notifications and delivery for that project.
- Invalid sound or toast position values fall back to global Settings values.
- Still deferred: config write path / chmod enforcement and settings UI.

## Phase 8: Release Readiness

Goal: make Roost usable as a standalone app.

Tasks:

- App icon and branding assets.
- Bundle id and signing identity.
- App entitlements audit (process spawning, file access scope, network for `jj git fetch`, XPC if hostd uses it).
- Notarization pipeline (hardened runtime, stapled ticket, CI signing).
- Sparkle feed replacement, with a migration path for any existing Muxy users on the old feed (one-time appcast bridge or fresh install only — pick and document).
- Homebrew cask plan.
- Crash/log export.
- Telemetry: opt-in by default; document the exact data collected before any code lands.
- Permission copy updates.
- README installation docs.
- License notices for Muxy, GhosttyKit, Sparkle, SwiftTerm, and other dependencies.

**Status (2026-04-28): Phase 8 (engineering subset) landed.**

- `THIRD_PARTY_LICENSES.md` bundles license texts for Muxy, Sparkle, SwiftTerm, libghostty.
- `README.md` adds Quickstart, Configuration, Architecture, Release, and Third-Party Licenses sections.
- `RELEASE-CHECKLIST.md` enumerates the human-driven release items: signing, notarization, Sparkle feed, Homebrew cask, telemetry, crash reporting, permissions audit, XPC service (deferred), pre-release smoke.
- **Phase 8 engineering work complete.** Distribution gates (Apple Developer Team ID, signing identity, notarization CI, app icon, Sparkle hosting, Homebrew cask submission) are tracked in `RELEASE-CHECKLIST.md` as human follow-up.

## Risk Register

- **jj working-copy snapshot race (product-level data safety)**: jj's working copy is a commit; any `jj status`/`log` invocation that omits `--ignore-working-copy` triggers a snapshot. Multi-agent writes can be silently captured into a change. Phase 1 snapshot policy is the mitigation; assume violations cause real data corruption.
- **Cross-process jj concurrency**: agents in panes invoke jj outside Roost's actor; only jj's own store lock applies. UI must assume any state can change between calls and rely on op-log fs-watch (Phase 4) for fresh-state signals.
- **jj sub-1.0 CLI drift**: command names, output, and templates change between releases (`branch` → `bookmark` is the canonical example). Mitigated by minimum-version pinning (Phase 0) and fixture-driven parser tests (Phase 1).
- **Swift 6 strict concurrency × blocking subprocess**: every jj call must be off-main, async, and cancellable; designed in Phase 1 as actor + AsyncStream, not retrofitted.
- **Persisted-state migration**: `projects.json` and any new Roost-side state must carry a schema version from Phase 0; field repurposing in Phase 2 (e.g. `ownsBranch`) is destructive without a migration test.
- **Upstream divergence**: large renames will make Muxy merges expensive.
- **Git assumptions**: Muxy's current VCS UI assumes branch/stage semantics in several places.
- **jj semantics**: bookmarks, working-copy commits, conflicts, and operation log need native UI language.
- **Terminal lifecycle**: Muxy terminal spawning is app-owned; Roost's desired persistent agents need hostd.
- **libghostty ABI**: a major libghostty bump can break GhosttyKit consumers; pin xcframework versions and gate upgrades behind manual smoke tests.
- **macOS sandbox + spawn**: hostd implementation choice (Phase 6) interacts with entitlements; XPC services and Unix sockets have different signing/notarization paths.
- **Sparkle feed migration**: replacing the Muxy feed risks orphaning existing installs; document the plan in Phase 8.
- **License attribution**: Muxy MIT license must remain intact.
- **Build artifacts**: legacy Roost Rust/Xcode artifacts must stay ignored on the Muxy-based mainline.

## Near-Term Task List

This list is the Phase 1 + Phase 2 spike scope; items overlap with later phase docs intentionally and are the bare-minimum surface to start.

1. Add jj service files behind no UI changes (`JjProcessRunner` actor, env contract, snapshot-default-off read APIs).
2. Add fixture-driven unit tests for jj output parsers (status, diff, op log) against the pinned minimum jj version.
3. Add repo detection for Git vs jj.
4. Add a hidden/internal jj workspace list path.
5. Adapt worktree creation to route jj repos through `jj workspace add` (covered jointly with Phase 2 field mapping).
6. Add first Roost agent preset commands.
7. Add a small Roost status panel showing active project, workspace, and session.
8. Re-run `scripts/checks.sh` (which includes `swift build`) after every phase.
