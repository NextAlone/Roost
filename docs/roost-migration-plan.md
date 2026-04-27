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
- Cardinality is **N sessions : 1 workspace** (default). Multiple terminals can share one jj workspace; opening a coding-agent preset *suggests* a new workspace but does not force one. 1:1 is selectable per agent preset. Cardinality decisions are baked into Phase 3 data model and cannot be reversed without migration, so this default is fixed before code lands.
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

Implementation stack — must be selected before Phase 6 begins (these three paths have incompatible packaging, signing, and sandbox stories):

1. **Swift rewrite + XPC service** — best macOS sandbox + entitlement story; loses old Rust code.
2. **Embed `roost-hostd` Rust binary + Unix socket** — reuses old code; needs group container entitlement and complicates notarization.
3. **Hybrid** — Swift wrapper, Rust core via FFI; highest implementation cost.

Until selection lands, do not start Phase 6 work. The decision affects entitlements, app bundle layout, and the Sparkle update channel.

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

