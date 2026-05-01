# Roost

Roost is a macOS-native, jj-first terminal orchestrator for multiple coding agents. It is built on the upstream Muxy SwiftUI + libghostty foundation, and the source tree intentionally keeps `Muxy/`, `MuxyShared/`, and `MuxyServer/` directory and module names to reduce upstream merge conflicts.

Requires macOS 14+ and Swift 6.0+. No external dependency managers are needed; everything is SPM-based.

## Build and Run

```bash
scripts/setup.sh
swift build
swift run Roost
```

## Linting and Formatting

Requires `swiftlint` and `swiftformat` (`brew install swiftlint swiftformat`).

```bash
scripts/checks.sh
scripts/checks.sh --fix
swiftformat --lint .
swiftlint lint --strict
```

Run `scripts/checks.sh --fix` after every task.

## Architecture

- The architecture of the app is documented at `./docs/architecture.md` and must stay current.
- `GhosttyService` manages the single `ghostty_app_t` instance per process.
- `GhosttyTerminalNSView` hosts a `ghostty_surface_t` and bridges terminal rendering/input into SwiftUI through `GhosttyTerminalRepresentable`.
- `AppState` manages projects, workspaces, tabs, split panes, and reducer-driven workspace actions.
- `WorktreeStore` persists per-project workspace/worktree slots; Git projects use Git worktrees, while jj projects map the compatibility `Worktree` model onto jj workspaces.
- `JjPanelState` / `JjPanelView` provide the jj-first Source Control panel for jj projects. Git projects still use the legacy Git VCS panel.

## Persistence

- Legacy app state and terminal integration files still live under `~/Library/Application Support/Muxy/` through `MuxyFileStorage`.
- App-wide Roost config lives at `~/Library/Application Support/Roost/config.json`.
- Project Roost config lives at `<project>/.roost/config.json`.
- Legacy `.muxy/worktree.json` is read only as a setup fallback.
- Host/session history lives under `~/Library/Application Support/Roost/hostd/`.

## Agent and Notification Notes

- Built-in agent kinds include Terminal, Claude Code, Codex, Gemini CLI, and OpenCode.
- Notification hooks currently use compatibility environment variables such as `MUXY_SOCKET_PATH` and `MUXY_PANE_ID`.
- The current notification socket path remains under `~/Library/Application Support/Muxy/muxy.sock`.

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
