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

## Quickstart

After `swift build`, launching Roost (`swift run Roost`) and opening a project gives you a sidebar with workspaces. Inside each project:

- Add a workspace: sidebar context menu → "New Workspace…"
- Open an agent tab: File → New Claude Code Tab / New Codex Tab / New Gemini CLI Tab / New OpenCode Tab
- View jj changes: ⌘K (Source Control) — current change card, file list, bookmarks, conflicts, mutating actions (describe / new / commit / squash / abandon / duplicate / backout)
- Session history: clock icon in sidebar footer

A jj-tracked project unlocks the full jj-first behaviour. Git-tracked projects continue to work via the legacy panel.

## Configuration

Roost reads `<project>/.roost/config.json` for per-project settings. Schema version 1 supports:

- `env`: environment variables shared by setup commands and agent presets; values can be plain strings or `{ "fromKeychain": "service", "account": "optional-account" }`
- `defaultWorkspaceLocation`: directory for newly created workspaces; relative paths resolve from the project root
- `setup`: list of `{ name?, command, cwd?, env? }` to run after creating a workspace
- `teardown`: list of `{ name?, command, cwd?, env? }` to run before removing a managed workspace
- `agentPresets`: list of `{ name, kind, command, env?, cardinality }` overrides for built-in agents (`kind` ∈ `terminal`, `claudeCode`, `codex`, `geminiCli`, `openCode`; `cardinality` ∈ `shared`, `dedicated`)

Example:

```json
{
  "schemaVersion": 1,
  "defaultWorkspaceLocation": ".roost/workspaces",
  "env": {
    "NODE_ENV": "development",
    "API_TOKEN": { "fromKeychain": "roost-api-token", "account": "default" }
  },
  "setup": [{ "name": "install", "command": "pnpm install", "env": { "CI": "1" } }],
  "teardown": [{ "name": "cleanup", "command": "pnpm clean", "cwd": "tools" }],
  "agentPresets": [
    {
      "name": "Claude Opus",
      "kind": "claudeCode",
      "command": "claude --model opus",
      "env": { "CLAUDE_CONFIG_DIR": ".roost/claude" },
      "cardinality": "dedicated"
    }
  ]
}
```

Legacy `.muxy/worktree.json` is still read as a fallback for `setup` only.

## Architecture

See [docs/architecture.md](docs/architecture.md) and [docs/roost-migration-plan.md](docs/roost-migration-plan.md) for the full architecture and migration plan.

## Release

See [RELEASE-CHECKLIST.md](RELEASE-CHECKLIST.md) for the manual handoff items (signing, notarization, telemetry, distribution).

## Third-Party Licenses

See [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for attribution of dependencies.

## License

Roost is currently based on Muxy, which is licensed under MIT. Keep upstream license and attribution intact while Roost-specific licensing is finalized.
