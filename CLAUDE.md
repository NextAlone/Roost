# Roost

Roost is a macOS-native, jj-first terminal orchestrator for multiple coding agents. It is built on the upstream Muxy SwiftUI + libghostty foundation, and the source tree intentionally keeps `Muxy/`, `MuxyShared/`, and `MuxyServer/` directory and module names to reduce upstream merge conflicts.

Requires macOS 14+ and Swift 6.0+. No external dependency managers are needed; everything is SPM-based.

## Build and Run

```bash
scripts/setup.sh
swift build
swift run Roost
```

`scripts/setup.sh` downloads `GhosttyKit.xcframework`, ghostty runtime resources, and a vendored `ripgrep` binary on first run; the project will not compile without it.

The Swift package builds three executables (`Roost`, `roost-hostd-daemon`, `RoostHostdXPCService`) plus the `RoostHostdCore`, `MuxyShared`, `MuxyServer`, and `GhosttyKit` libraries. `roost-hostd-daemon` is a standalone helper used by the `hostdOwnedProcess` runtime mode and is launched out of the app bundle at runtime.

## Tests

```bash
swift test
swift test --filter RoostTests.WorkspaceReducerTests
swift test --filter RoostTests.WorkspaceReducerTests/testCreatesTabInDirectory
```

The test target lives in `Tests/MuxyTests/` (the directory name still uses the upstream Muxy prefix; the SwiftPM target is `RoostTests`). Tests run hostd in `metadataOnly` mode and do not require `tmux` on `PATH`.

## Linting and Formatting

Requires `swiftlint` and `swiftformat` (`brew install swiftlint swiftformat`). Tool versions are pinned in `.tool-versions` and `scripts/checks.sh` validates them on startup; set `ROOST_SKIP_TOOL_VERSION_CHECKS=1` to bypass when iterating with a different local version.

```bash
scripts/checks.sh
scripts/checks.sh --fix
swiftformat --lint .
swiftlint lint --strict
```

Run `scripts/checks.sh --fix` after every task. The script uses an isolated SwiftPM build path (`$TMPDIR/roost-spm-build-<workspace-hash>`) to avoid clobbering the default `.build/` directory used by `swift build` / IDE indexing.

## Architecture

- The architecture of the app is documented at `./docs/architecture.md` and must stay current.
- `GhosttyService` manages the single `ghostty_app_t` instance per process.
- `GhosttyTerminalNSView` hosts a `ghostty_surface_t` and bridges terminal rendering/input into SwiftUI through `GhosttyTerminalRepresentable`.
- `AppState` manages projects, workspaces, tabs, split panes, and reducer-driven workspace actions.
- All workspace state mutations must go through `AppState.dispatch(Action) → WorkspaceReducer.reduce`. Do not mutate `AppState` workspace fields directly; the reducer returns immutable state plus `WorkspaceSideEffects` (pane create/destroy) that `AppState` then applies via `TerminalViewRegistry`.
- `WorktreeStore` persists per-project workspace/worktree slots; Git projects use Git worktrees, while jj projects map the compatibility `Worktree` model onto jj workspaces.
- `JjPanelState` / `JjPanelView` provide the jj-first Source Control panel for jj projects. Git projects still use the legacy Git VCS panel.

## Persistence

- App state and terminal integration files live under `~/Library/Application Support/Roost/` through `MuxyFileStorage`.
- App-wide Roost config lives at `~/Library/Application Support/Roost/config.json`.
- Project Roost config lives at `<project>/.roost/config.json`.
- Legacy `.muxy/worktree.json` is read only as a setup fallback.
- Host/session history lives under `~/Library/Application Support/Roost/hostd/`.

## Hostd Runtime

- `hostdRuntime` in app config selects between `metadataOnly` (default; no daemon, no agent persistence) and `hostdOwnedProcess` (launches `roost-hostd-daemon` and persists agent sessions across app restarts).
- `hostdOwnedProcess` requires `tmux` on `PATH`. Agent panes (`agentKind != .terminal`) are owned by `tmux new-session -d -s roost-<session-id>`; missing or failing `tmux` puts the pane into the failed state with the tmux error.
- The daemon socket is `/tmp/roost-hostd-daemon-$uid.sock`. Sockets from older daemons whose `HostdDaemonRuntimeIdentity` protocol version mismatches the app are treated as unavailable and replaced.

## Agent and Notification Notes

- Built-in agent kinds include Terminal, Claude Code, Codex, Gemini CLI, and OpenCode.
- Each terminal surface receives `ROOST_PANE_ID`, `ROOST_PROJECT_ID`, `ROOST_WORKTREE_ID`, and `ROOST_SOCKET_PATH` env vars; the `MUXY_*` aliases (`MUXY_SOCKET_PATH`, `MUXY_PANE_ID`, …) are exported as legacy compatibility only — prefer the `ROOST_*` names in new code and wrappers.
- The current notification socket path is `~/Library/Application Support/Roost/roost.sock`.

## NSViewRepresentable Pitfalls

- Never return a cached or reused NSView from `makeNSView`. SwiftUI assumes it gets a fresh view and can break silently when it does not.
- To keep an NSView alive across tab switches, keep the `NSViewRepresentable` mounted in the view tree rather than conditionally removing it and relying on a registry cache.
- When debugging blank or empty NSView issues, first check whether the NSView is being remounted from a detached state.

## Main Rules

- No commenting allowed in the codebase.
- All code must be self-explanatory and cleanly structured.
- Use early returns instead of nested conditionals.
- Do not patch symptoms; fix root causes.
- Consider architecture and code quality impact for every task.
- Follow existing patterns, and offer refactors when they improve maintainability.
- Use logs for debugging.
- If the feature is testable, write tests.
- Keep PR descriptions short.
- Upload screenshots or recordings for PRs that change UI.
- Never answer codebase questions without checking local context first.

## Code Review

- Review PRs and code against the purpose of the requested change. Report unrelated issues in a separate section.
- Apply review recommendations only after user confirmation.

## Humans-Only GitHub Text (CONTRIBUTING.md)

AI-generated text is **not allowed** in GitHub issue / PR titles, descriptions, summaries, comments, or code-review comments. AI may help write code, but any text posted on GitHub must be authored by a human in their own words. When asked to draft a PR description or issue body, prepare the content as a draft for the user to rewrite in their own voice rather than posting it directly.
