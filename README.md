# Roost

macOS native, jj-first terminal orchestration for multiple coding agents.

Roost is being rebuilt on top of the upstream Muxy codebase so it can inherit a solid SwiftUI + libghostty terminal foundation while adding jj-native workspaces, agent sessions, and Roost-specific orchestration.

## Baseline

- Upstream: https://github.com/muxy-app/muxy
- Current tracked upstream bookmark: `vendor/muxy-main`
- App baseline: Swift Package, Swift 6, macOS 14+, SwiftUI, libghostty, Sparkle

The initial Roost mainline intentionally keeps the upstream directory layout (`Muxy/`, `MuxyShared/`, `MuxyServer/`) to reduce future merge conflicts with Muxy. Roost-specific code should be added incrementally instead of doing a full directory rename up front.

## Direction

- Keep Muxy's terminal, split-pane, project/workspace persistence, settings, theme, and remote-control foundations.
- Replace Git-first worktree behavior with jj-first workspace/change/bookmark behavior.
- Add agent-aware sessions for Claude Code, Codex, Gemini CLI, OpenCode, and plain terminals.
- Later migrate selected host/session persistence ideas from the old Roost `feat-m6` line.

## Local Development

```bash
scripts/setup.sh
swift build
swift run Roost
```

## License

Roost is currently based on Muxy, which is licensed under MIT. Keep upstream license and attribution intact while Roost-specific licensing is finalized.
