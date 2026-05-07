# Agent Reload and Resume Design

## Goal

Provide a fast, single-click path to restart a coding agent inside an existing Roost pane after the user upgrades the agent's binary (for example `brew upgrade claude`, `npm i -g @anthropic-ai/claude-code`, or a Codex update). When the agent prints a resume command on exit, Roost captures that command from the tmux pane and stitches the resume arguments onto the user's preset command, preserving the conversation session across the binary swap.

## Non-Goals

- Reload support for `metadataOnly` runtime panes. The first phase only targets `hostdOwnedProcess` panes that own a tmux session. Banner and menu entries are gated off when `pane.hostdRuntimeOwnership != .hostdOwnedProcess`.
- Reload for `.terminal` agent kind. The preset / resume model only applies to coding agents.
- A keyboard shortcut for reload. The interaction surface in this iteration is the pane context menu plus pane-top banners.
- Active push notification when a binary changes mid-session. Detection happens lazily on pane focus.
- A preset editor UI for `resumeCommandRegex`. Overrides are read from JSON config only in this phase.
- Reload semantics for cases where the user changed their preset configuration. The implementation will naturally use the latest preset on reload, but UI does not surface "preset changed" as a distinct trigger.

## Background

Roost runs coding agents through tmux when `hostdRuntime = hostdOwnedProcess`. `RoostHostdCore.HostdTmuxController` invokes `tmux new-session -d -s roost-<session-id> ... -- <agent command>`, and `GhosttyTerminalNSView` renders the session by spawning `tmux attach-session -t roost-<session-id>` inside its own PTY. Hostd never reads the agent's stdout directly; tmux owns the PTY, scrollback, and lifecycle.

This means a previously considered design ("add a ring buffer inside `HostdPTYSession`") does not work for agent panes. `HostdPTYSession` is only used for ordinary terminal panes. To capture the resume hint that an agent prints on exit, Roost must read it through tmux.

Empirical validation (`tmux 3.6a`, macOS 14):

```
$ tmux new-session -d -s test -- bash -c 'echo "Resume with: claude --resume abc"; exit 0' \
    \; set-option -t test remain-on-exit on
$ tmux list-panes -t test -F '#{pane_dead}'
1
$ tmux capture-pane -t test:0.0 -p -S -50 -N
session continuing

Resume with: claude --resume abc

...
Pane is dead (status 0, ...)
```

`remain-on-exit on` keeps the tmux pane after its child process exits, `pane_dead` becomes `1`, and `capture-pane -p -S <n> -N` returns the pane's text history without ANSI escapes. This is the foundation for the design.

## Decision

Use tmux as the capture surface. On agent launch, set `remain-on-exit on` for the Roost-owned tmux session. Hostd's existing exit watcher polls `pane_dead`, runs `capture-pane` once the pane is dead, transmits the captured tail to the app over the daemon socket, and only then kills the tmux session.

The app extracts a resume command from the captured tail using a regex per `AgentKind` (overridable per preset), records it on the pane, and renders banners that let the user reload with or without resume.

Reload itself destroys the old ghostty surface and creates a new one for the same `paneID` but a new `sessionID`. The new launch command is `preset.defaultCommand` followed by the resume arguments extracted from the captured command (or just `preset.defaultCommand` for a fresh restart).

## Architecture

```text
[hostd]  HostdTmuxController.launch(...)
            tmux new-session -d ... -- <command> \; set-option remain-on-exit on

[hostd]  HostdProcessRegistry.startExitWatcher  (poll, ~500ms)
            hasSession? no  -> exited(lastTail: nil), break
            hasSession? yes -> isPaneDead?
                no  -> sleep
                yes -> tail = captureLastTail(name, lines: 200)
                       notify(SessionExit, lastTail: tail)
                       killSession
                       break

[app]    AppState.handleSessionExit(paneID, lastTail)
            regex = preset.resumeCommandRegex ?? agentKind.defaultResumeRegex
            captured = regex.firstMatch(lastTail)
            dispatch(.markPaneSessionExited(paneID, capturedResumeCommand: captured))
            ActivityLogStore.append(.agentExited(paneID, captured: captured != nil))

[app]    pane focus
            refreshBinaryUpdateBanner(paneID)
              compare snapshot mtime vs current mtime
              dispatch(.setBinaryUpdateDetected(paneID, value:))

[user]   reload trigger (context menu | exit banner | mtime banner)
            dispatch(.reloadAgent(paneID, mode: .resume | .fresh))
              kill old session
              destroy ghostty surface for paneID
              command = buildReloadCommand(preset, captured, mode)
              create new session (new sessionID, same paneID, same cwd, refreshed env)
```

## Data Model

### Preset config (`MuxyShared/Config/RoostConfigAgentPreset.swift`)

The JSON-decodable preset type lives in `RoostConfigAgentPreset`, which is converted to the in-memory `AgentPreset` (`MuxyShared/Agent/AgentPreset.swift`) by `AgentPresetCatalog.preset(for:configuredPresets:)`. The new field must be threaded through both layers:

```swift
public struct RoostConfigAgentPreset: Codable, Hashable {
    public let kind: AgentKind
    public let defaultCommand: String
    public let env: [String: String]
    public let requiresDedicatedWorkspace: Bool
    public let resumeCommandRegex: String?   // new, nil → use AgentKind default
}

public struct AgentPreset: Sendable, Hashable {
    public let kind: AgentKind
    public let defaultCommand: String
    public let env: [String: String]
    public let requiresDedicatedWorkspace: Bool
    public let resumeCommandRegex: String?
}
```

`AgentPresetCatalog` copies the field across when materializing `AgentPreset` from the configured preset. `AgentPreset.resumeCommandRegex` is consumed at runtime; `RoostConfigAgentPreset.resumeCommandRegex` is the on-disk source of truth.

### `AgentKind.defaultResumeRegex` (computed, hardcoded)

| Kind | Regex (NSRegularExpression syntax) |
| --- | --- |
| `.claudeCode` | `(?m)^\s*claude\s+--resume\s+\S+.*$` |
| `.codex` | `(?m)^\s*codex\s+resume\s+\S+.*$` |
| `.geminiCli` | `nil` (no native resume in this phase) |
| `.openCode` | `nil` (follow-up) |
| `.terminal` | `nil` (not applicable) |

### `TerminalPaneState`

Add fields:

```swift
var sessionID: UUID                    // new — mirrors hostd SessionRecord.id; set on session create, replaced on reload
var capturedResumeCommand: String?
var agentBinaryPath: URL?
var agentBinaryMTime: Date?
var binaryUpdateDetected: Bool
var exitBannerDismissed: Bool
var mtimeBannerDismissed: Bool
```

`sessionID` exists today only inside `HostdAttachSessionResponse.record.id`; lifting it onto `TerminalPaneState` is required so `GhosttyTerminalRepresentable.id(pane.sessionID)` can drive SwiftUI to recreate the NSView on reload. Today the same need is met implicitly by tearing down the whole pane when the agent exits; we now keep the pane while replacing the session, so the binding becomes load-bearing.

`capturedResumeCommand`, `binaryUpdateDetected`, and the dismissed flags reset on reload. `agentBinaryPath` / `agentBinaryMTime` are re-snapshotted on each reload.

### `TerminalTabSnapshot` (persistence)

Pane state crosses app restarts via `TerminalTabSnapshot` (`Muxy/Models/WorkspaceSnapshot.swift`). Field-by-field decisions:

| New `TerminalPaneState` field | Persist in `TerminalTabSnapshot`? | Reasoning |
| --- | --- | --- |
| `sessionID` | yes | needed to re-attach to a hostd session at app launch |
| `capturedResumeCommand` | no | recovered from `SessionRecord.lastTail` (DB) when the daemon side is durable; in-memory state stays simple |
| `agentBinaryPath` / `agentBinaryMTime` | no | re-snapshotted on next reload; mtime banner is a focus-time check |
| `binaryUpdateDetected` | no | recomputed on focus |
| `exitBannerDismissed` / `mtimeBannerDismissed` | no | dismissals are per-session; banner state recomputes on launch |

`SessionRecord.lastTail` is the durable source of truth for captured resume hints across restarts; in-memory `TerminalPaneState.capturedResumeCommand` is repopulated lazily from the daemon on session re-attach.

### `SessionRecord` (`RoostHostdCore/SessionStore.swift`)

```swift
public struct SessionRecord {
    // existing fields are immutable `let`. The new field is also stored as `let`,
    // populated only at construction and replaced via record(...) on update.
    public let lastTail: String?
}
```

The struct stays value-typed and immutable; updating the captured tail goes through `SessionStore.record(_:)` (which already writes a fresh struct). The `update()` and `record()` helpers gain a `lastTail` parameter and write it as part of the existing UPSERT.

**SQLite migration**: `user_version` bumps from 1 to 2.

```sql
ALTER TABLE sessions ADD COLUMN last_tail TEXT;
```

The migration is additive and idempotent. `SessionStore.openDatabase` runs the migration at startup when `user_version < 2`.

Captured tail is persisted to the SQLite session store so a reload that follows an app restart can still recover the resume command.

### IPC

`HostdSessionExitNotice` gains a `lastTail: String?` field. `HostdDaemonRuntimeIdentity.protocolVersion` is bumped by 1; the existing mismatch handling will trigger socket replacement against older daemons.

## Hostd Changes

`HostdTmuxControlling` protocol additions:

```swift
func isPaneDead(sessionName: String) async -> Bool
func captureLastTail(sessionName: String, lines: Int) async -> String?
```

Concrete implementation in `HostdTmuxController`:

- `isPaneDead`: runs `tmux list-panes -t <name> -F '#{pane_dead}'`, returns `output == "1"`.
- `captureLastTail`: runs `tmux capture-pane -t <name>:0.0 -p -S -<lines> -N`, strips lines containing the literal `Pane is dead` marker tmux appends, returns the resulting string. Errors return `nil`; the caller treats `nil` as "no tail available".

`HostdTmuxController.launchArguments` is extended so the `set-option` argument list includes `set-option -t <sessionName> remain-on-exit on` alongside the existing options. The change is local to the Roost-owned session and does not affect any unrelated tmux sessions.

**Watcher placement (correction)**: today `startExitWatcher` is only invoked from the PTY path inside `HostdProcessRegistry`; the tmux launch path (`launchTmuxSession`) has no exit watcher at all. This spec **adds** a tmux-specific watcher (`startTmuxExitWatcher(id:sessionName:)`) and wires it from `launchTmuxSession`. Wording in earlier sections that said "rewrite startExitWatcher" should be read as "add the tmux variant with the loop described above." The PTY watcher is unchanged.

```text
startTmuxExitWatcher(id, sessionName):
  loop:
    if not tmux.hasSession(sessionName):
        notify(id, .exited(lastTail: nil))
        return
    if tmux.isPaneDead(sessionName):
        tail = tmux.captureLastTail(sessionName, lines: 200)
        notify(id, .exited(lastTail: tail))
        try? tmux.killSession(sessionName)
        return
    sleep(paneDeadPollNanoseconds)   // 500ms
```

The `notify` step writes `lastTail` to `SessionStore` (via `record(_:)`) and emits the IPC SessionExit notice carrying the same value. `tmux.killSession` is best-effort; failures are logged but do not block exit propagation.

`HostdDaemonSocketServer` is updated to encode the new `lastTail` field on the SessionExit message and bump the protocol version constant.

## App Changes

`AppState`:

- `handleSessionExit(paneID:sessionID:lastTail:)`: looks up preset, runs regex, dispatches `.markPaneSessionExited(paneID, capturedResumeCommand:)`, writes ActivityLogStore event.
- `reloadAgent(paneID:mode:)`: dispatches `.reloadAgent(paneID, mode:)`. Concurrency guard: maintains `inFlightReloadPaneIDs: Set<UUID>`; second reload before the first completes is ignored.
- `refreshBinaryUpdateBanner(paneID:)`: compares `pane.agentBinaryMTime` snapshot with `FileManager.attributesOfItem(atPath:)[.modificationDate]` for `pane.agentBinaryPath`. Dispatches `.setBinaryUpdateDetected(paneID, value:)` when the result changes.

`WorkspaceAction` adds:

```swift
case markPaneSessionExited(paneID: UUID, capturedResumeCommand: String?)
case reloadAgent(paneID: UUID, mode: AgentReloadMode)
case setBinaryUpdateDetected(paneID: UUID, value: Bool)
case dismissExitBanner(paneID: UUID)
case dismissBinaryUpdateBanner(paneID: UUID)

enum AgentReloadMode { case resume, fresh }
```

**Reducer scope vs. AppState orchestration**: `WorkspaceSideEffects` is currently a struct with `paneIDsToRemove` and `projectIDsToRemove` (no associated-value enum cases). Rather than reshape that struct to carry rich create/destroy operations (which would ripple through every existing action), `.reloadAgent` is split:

- The **reducer** only updates `TerminalPaneState` — clears `capturedResumeCommand` / banner flags, refreshes `agentBinaryPath` / `agentBinaryMTime`, replaces `sessionID` with a fresh UUID, sets `lastState = .preparing`. It does not touch `WorkspaceSideEffects`.
- `AppState.reloadAgent(paneID:mode:)` orchestrates the imperative side, in this order:
  1. `inFlightReloadPaneIDs.insert(paneID)`; bail if already present.
  2. Capture `oldSessionID = pane.sessionID`, `newSessionID = UUID()`.
  3. If pane was running, run the SIGINT escalation described below; await `.exited`.
  4. `roostHostdClient.terminateSession(oldSessionID)` (returns when the daemon acknowledges; existing API).
  5. `terminalViewRegistry.removeView(for: paneID)` (existing API name; spec elsewhere had `destroy`, that is the wrong identifier — `removeView` is the right one).
  6. Dispatch `.reloadAgent(paneID, mode, newSessionID, command, env, cwd, agentBinaryPath, agentBinaryMTime)` to the reducer to update state.
  7. Call into the existing session create path (`roostHostdClient.createSession(...)`), with the new `command` / `env` / `cwd` / `agentKind`. The pane re-mounts via the normal `TerminalPane.body` path because `pane.sessionID` (now `newSessionID`) drives `.id(...)` on `GhosttyTerminalRepresentable`.
  8. `inFlightReloadPaneIDs.remove(paneID)` regardless of success or failure.

Because the destruction and creation are imperative rather than reducer side effects, this design avoids reshaping `WorkspaceSideEffects` and keeps `WorkspaceReducer` purely state-transition. The cost is that reload becomes an `AppState` async method that drives both the reducer and the daemon directly — consistent with how other lifecycle operations (e.g. `closeArea`) already work in `AppState`.

`buildReloadCommand` is **per-kind**, because the way each agent expresses resume differs structurally:

| Kind | Resume expression | Strategy |
| --- | --- | --- |
| `.claudeCode` | flag (`claude --resume <id>`) — composable with other top-level flags | `.appendArgs`: `preset.defaultCommand + " " + extractedArgs`. Preset flags like `--dangerously-skip-permissions` survive. |
| `.codex` | subcommand (`codex resume <id>`) — top-level flags before a subcommand are **not** universally valid | `.replaceWithCaptured`: use the captured command verbatim (after metachar validation). Preset flags are dropped on resume; `.fresh` keeps them. This is a deliberate trade-off documented to the user. |
| `.geminiCli` | not supported in this phase | `.notSupported`: `.resume` falls back to `.fresh` with banner messaging. |
| `.openCode` | not supported until upstream behavior is examined | `.notSupported`. |
| `.terminal` | not applicable | not exposed. |

The strategy is encoded as `AgentKind.resumeStrategy: ResumeStrategy` (computed):

```swift
enum ResumeStrategy {
    case appendArgs      // preset.defaultCommand + " " + extractedArgs
    case replaceWithCaptured  // captured command, verbatim
    case notSupported
}

func buildReloadCommand(
    preset: AgentPreset,
    captured: String?,
    mode: AgentReloadMode
) -> String {
    guard mode == .resume, let captured else { return preset.defaultCommand }
    switch preset.kind.resumeStrategy {
    case .notSupported:
        return preset.defaultCommand
    case .replaceWithCaptured:
        guard ResumeArgs.captureLooksValid(captured, kind: preset.kind) else {
            return preset.defaultCommand
        }
        return captured
    case .appendArgs:
        guard let resumeArgs = AgentBinary.stripBinaryName(from: captured, kind: preset.kind),
              !ResumeArgs.containsShellMetacharacters(resumeArgs)
        else { return preset.defaultCommand }
        return "\(preset.defaultCommand) \(resumeArgs)"
    }
}
```

`ResumeArgs.captureLooksValid` for `.replaceWithCaptured` checks that:
- the first whitespace-separated token matches the kind's expected binary name (`codex`),
- the captured string contains no shell metacharacters (`;`, `|`, `&`, `` ` ``, `$(`, newlines, redirections `>` `<`).

`AgentBinary.stripBinaryName` (used only by `.appendArgs`) removes the leading binary token from a captured command (`"claude --resume abc" → "--resume abc"`). It uses simple whitespace tokenization, supports an optional absolute path prefix, and matches the kind's expected binary name (`claude`, `codex`, etc.). If the captured command does not start with the expected binary name, the function returns `nil`; the reload falls back to `.fresh` semantics with a logged warning so we never produce a malformed command line.

`AgentBinary.resolvePath(command:env:)`: takes the first whitespace-separated token, treats absolute paths verbatim, and otherwise consults the pane's `PATH` env via `which`. Returns `nil` when the binary is unresolvable; the binary update banner feature simply turns off for that pane.

`ActivityLogStore` gains two event variants: `.agentExited(paneID, captured: Bool)` and `.agentReloaded(paneID, mode: AgentReloadMode)`. They live alongside the existing `agentActivity` events.

## UI

Three entry points, all mutually consistent.

### Pane context menu

`Muxy/Views/Workspace/TerminalPaneContextMenu.swift` adds two items, gated on `pane.agentKind != .terminal && pane.hostdRuntimeOwnership == .hostdOwnedProcess`:

- "Reload Agent (Resume)" — disabled when `pane.lastState == .running && pane.capturedResumeCommand == nil`. Dispatch `reloadAgent(paneID, .resume)`.
- "Reload Agent (Fresh)" — always enabled. Dispatch `reloadAgent(paneID, .fresh)`.

When the user picks "Resume" while the agent is still running, `AppState` first asks hostd to interrupt the running agent. The needed call is **new** to `RoostHostdClient`: `interruptSession(id:)`. Implementation: in `LocalHostdClient` and the daemon-socket client, the call dispatches a tmux `send-keys -t roost-<id> C-c` request through the existing IPC envelope. The daemon then runs `tmux send-keys -t <name> C-c` against the Roost-owned tmux session, which delivers `SIGINT` to the agent process inside the pane.

This is intentionally distinct from the existing `sendSessionSignal(id:signal:)` call: that call signals the PTY child that hostd holds, but for tmux-owned panes the PTY child is `tmux attach`, not the agent. Sending a Unix signal there does not reach the agent. `send-keys C-c` does.

The reload coordinator then waits for `pane.lastState == .exited` with a tiered timeout, because some agents (Claude Code) require a second `Ctrl-C` to confirm exit:

1. Wait up to 3s for `.exited`.
2. If still running, send `C-c` a second time. Wait another 3s.
3. If still running, send `tmux kill-session` directly (force-kill). The force-kill path also clears `tmuxAttachedClientCounts[id]` in `HostdProcessRegistry` so the bookkeeping does not drift; otherwise a subsequent `releaseSession` call would attempt to decrement against an already-dead session. The exit watcher will report `.exited` with `lastTail = nil` because the pane was killed before printing a resume hint.
4. If `capturedResumeCommand` is still `nil` after `.exited` is reached, the pane stays exited and the exit banner is shown with `Resume` disabled. The user picks `Restart fresh` or dismisses.

Total worst-case latency from menu click to UI response: ~6s. The pane is decorated with a transient "Reloading…" overlay during the wait so the user knows the action is in flight.

### Exit banner

`AgentExitBannerView` is a SwiftUI overlay attached to the pane via `.overlay(alignment: .top)`. It does not push the ghostty surface down. Visible when `pane.lastState == .exited && !pane.exitBannerDismissed`.

```
┌──────────────────────────────────────────────────────────┐
│ Agent exited.   [Resume]   [Restart fresh]   [Dismiss]   │
└──────────────────────────────────────────────────────────┘
```

`Resume` is disabled with a tooltip `Resume command not detected — restart fresh` when `pane.capturedResumeCommand == nil`.

### Binary update banner

Same overlay component, alternative layout:

```
┌──────────────────────────────────────────────────────────┐
│ ⟳ claude binary updated since launch.   [Reload]   [✕]   │
└──────────────────────────────────────────────────────────┘
```

Visible when `pane.binaryUpdateDetected && !pane.mtimeBannerDismissed && pane.lastState == .running`. `[Reload]` dispatches `reloadAgent(paneID, .resume)` (so the user keeps their conversation through the upgrade).

Detection runs from `TerminalPane.body` via `.onChange(of: focusedPaneID)`, `.onAppear`, and `.onChange(of: scenePhase)` (so returning the app to the foreground re-checks the focused pane). When a pane gains focus, `AppState.refreshBinaryUpdateBanner(paneID)` is called. Result is dispatched only when it changes value, to avoid redundant reducer churn.

### Banner priority

The two banners are mutually exclusive in practice: the exit banner only shows when `pane.lastState == .exited`, the mtime banner only when `.running`. Both check `pane.lastState` independently; no extra priority logic is needed.

### Theming

Banners reuse `RoostTheme` colors and corner radii. Primary action button uses `.borderedProminent`, secondary `.bordered`.

## Reload Flow Detail

```text
.reloadAgent(paneID, mode)
   │
   ├─ guard !inFlightReloadPaneIDs.contains(paneID); else return
   ├─ insert paneID
   ├─ pane = pane(paneID)
   ├─ preset = preset(for: pane.agentKind)
   ├─ command = buildReloadCommand(preset, pane.capturedResumeCommand, mode)
   ├─ env = TerminalPaneEnvironment.build(paneID, pane.worktreeKey, preset.env)
   ├─ cwd = pane.cwd
   ├─ binaryPath = AgentBinary.resolvePath(command, env)
   ├─ binaryMTime = mtime(binaryPath)
   │
   ├─ side effects:
   │     .destroyTerminalPane(paneID, sessionID: pane.sessionID)
   │     .createTerminalPane(
   │         paneID,
   │         sessionID: UUID(),
   │         command, env, cwd, agentKind: pane.agentKind,
   │         agentBinaryPath: binaryPath,
   │         agentBinaryMTime: binaryMTime
   │     )
   │
   ├─ AppState.applySideEffects:
   │     - tmux.killSession(old) (best-effort, log on failure)
   │     - TerminalViewRegistry.destroy(paneID)  → ghostty surface released
   │     - hostd.createSession(...) → new SessionRecord
   │     - new GhosttyTerminalNSView mounts via TerminalPane body
   │
   ├─ remove paneID from inFlightReloadPaneIDs (on completion or failure)
   └─ ActivityLogStore.append(.agentReloaded(paneID, mode))
```

`GhosttyTerminalRepresentable` is bound with `.id(pane.sessionID)`. Because `sessionID` changes across reload, SwiftUI tears down the old `NSViewRepresentable` instance and creates a new one, sidestepping the "do not reuse NSView" pitfall noted in `CLAUDE.md`.

**Scrollback consequence**: tearing down the old ghostty surface drops its scrollback. After reload the user sees only the new agent's startup output. The previously visible conversation history (and the captured resume hint that drove the reload) are gone from the visible terminal even though the agent's own session continues. This is acceptable for the binary-upgrade use case (fresh terminal, same conversation), but the spec calls it out so the UX trade-off is explicit. The captured resume command itself is preserved in `pane.capturedResumeCommand` until the next exit, and persisted to `SessionRecord.lastTail` on disk, so a follow-up audit / debug path remains.

## State Preservation Matrix

| Field | Across reload |
| --- | --- |
| `paneID` | preserved |
| `sessionID` | new UUID |
| `cwd` | preserved (worktree path) |
| `env` | recomputed via `TerminalPaneEnvironment.build` so `ROOST_*` vars remain consistent and any preset env changes pick up |
| `agentKind` | preserved |
| `startupCommand` | recomputed (`preset.defaultCommand` + optional resume args) |
| `agentBinaryPath` / `agentBinaryMTime` | re-snapshotted at reload time |
| `capturedResumeCommand` | cleared |
| `binaryUpdateDetected` | reset to `false` |
| `exitBannerDismissed` / `mtimeBannerDismissed` | reset to `false` |
| `lastState` | `.preparing → .running` |
| Tab / split position / focus | unchanged (paneID unchanged, layout untouched) |

## Failure Handling

| Stage | Failure | Behavior |
| --- | --- | --- |
| `tmux killSession` for old | non-zero status | log warning, continue. Orphan tmux session is a known edge; user can clean up via tmux directly. |
| `tmux launch` for new | non-zero status | pane transitions to `.failed(message)` per existing path; banner cleared; user retries via context menu. |
| capture regex no match | regex returns `nil` | `capturedResumeCommand = nil`; exit banner shows with `Resume` disabled. No automatic fallback. |
| Captured command contains shell metacharacters | regex matches but result has `;` `|` `&` `` ` `` `$(` | reducer treats it as untrusted, logs warning, falls back to `.fresh` semantics, banner shows a tooltip explaining. |
| `which` fails for `AgentBinary.resolvePath` | binary path unresolved | mtime banner feature disabled silently for that pane; reload still works with `pane.cwd`-relative invocation. The pane title tooltip notes "binary update detection unavailable" and a one-shot debug log records the resolution attempt so Nix / asdf / shim users can spot why no banner appears. |
| Daemon protocol mismatch | identity check fails | existing socket replacement logic takes over; no new code path needed. |

## Configuration

`AgentPreset` JSON files (per-project `.roost/config.json` and global `~/Library/Application Support/Roost/config.json`) accept a new optional `resumeCommandRegex` field. Example override for a customized Claude wrapper:

```json
{
    "presets": [
        {
            "kind": "claudeCode",
            "defaultCommand": "claude --dangerously-skip-permissions",
            "resumeCommandRegex": "(?m)^\\s*claude\\s+(--continue|--resume\\s+\\S+).*$"
        }
    ]
}
```

A missing or invalid regex falls back to `AgentKind.defaultResumeRegex`. Regex compilation happens once per preset load and the compiled value is cached on the preset.

## Testing

### Unit

- `HostdTmuxControllerTests`: mock `run(arguments:)` and verify
  - `launchArguments` includes the `remain-on-exit on` `set-option` triple
  - `isPaneDead` matches `output == "1"` exactly
  - `captureLastTail` issues `tmux capture-pane -t <name>:0.0 -p -S -<lines> -N` and strips `Pane is dead` lines.
- `AgentResumeExtractorTests`: fixtures for Claude / Codex exit output (clean, with leading whitespace, with ANSI escapes that survived the `-N` flag, multiple matches selecting the last) feeding `AgentKind.defaultResumeRegex`.
- `AgentBinaryResolverTests`: absolute path, `which` lookup using a synthetic `PATH`, quoted command, command with embedded spaces.
- `WorkspaceReducerTests`:
  - `.reloadAgent(.resume)` with a captured value produces a command containing `--resume <id>` and emits the expected destroy + create side effects.
  - `.reloadAgent(.fresh)` produces only `preset.defaultCommand`.
  - `.reloadAgent(.resume)` with a captured value containing shell metacharacters (`;`, `|`, `&`, `` ` ``, `$(`) falls back to `.fresh` semantics and logs a warning.
  - `.reloadAgent(.resume)` with a captured value whose binary token does not match the kind falls back to `.fresh` semantics.
  - `.reloadAgent` while a previous reload is in flight is dropped.
  - State preservation matrix is satisfied by the resulting `TerminalPaneState`.

### Integration

`Tests/MuxyTests/Integration/AgentReloadIntegrationTests.swift`, gated on `tmux` availability:

- Launch a fake agent via `bash -c 'echo "claude --resume xyz"; sleep 0.1; exit 0'` through `HostdTmuxController.launch` with the new options.
- Poll `isPaneDead` until true (with timeout).
- Call `captureLastTail`, assert the captured string contains `claude --resume xyz`.
- Drive `reloadAgent` end to end, verify the new `SessionRecord.id` differs from the old, the old tmux session is killed, and the new tmux session is alive.
- Skip the test when `tmux` is missing.

### Manual

- Run on macOS 14 with `tmux 3.6+`, real Claude Code and Codex binaries.
- Confirm the agent's exit hint is captured and the resume reload reuses the conversation.
- For Gemini CLI panes, verify the exit banner offers only `Restart fresh`.
- Trigger `brew upgrade claude`, focus the pane, confirm the mtime banner appears and `[Reload]` swaps the binary.
- While the agent is `.running`, pick "Reload Agent (Resume)" from the context menu and confirm the SIGINT → exit → reload sequence completes.
- In a split pane, reload one pane and confirm the sibling pane is unaffected.
- Dismiss the banner, then `touch <binary>` again and re-focus; the banner should reappear (dismissal applies to the previously detected mtime).

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Claude Code or Codex change their resume hint format. | Per-preset `resumeCommandRegex` override; default regex tracked alongside upstream changes. |
| `remain-on-exit on` interferes with user expectations of tmux. | Option is set only on Roost-owned sessions (`roost-<id>`). User-owned tmux sessions are untouched. |
| Wrapped lines split a captured command across two tmux history rows. | `-S -200` and `-N` give enough scrollback; multi-line wrap of a single resume command is unlikely in practice. Documented as a known limitation; users can override the regex with a multi-line pattern if needed. |
| Agent crashes via `SIGKILL` and never prints a hint. | Captured value is `nil`; banner offers `Restart fresh` only. Acceptable behavior. |
| `which`-based binary resolution differs from the actual launched binary (Nix, asdf, multiple shims). | `AgentBinary.resolvePath` uses the pane's `PATH`, not the app process `PATH`. Failure path is graceful (banner disabled), no incorrect reload. |
| Concurrent reloads on the same pane. | `inFlightReloadPaneIDs` guard. The set is in-memory only and **deliberately** not persisted: on app start the set is empty, which is the correct behavior because there is by definition no in-flight reload across an app launch. If the previous session was mid-reload when the app died, the user simply re-triggers reload. |
| Daemon protocol bump breaks an in-flight session shared with an older app. | Existing identity mismatch path replaces the daemon socket; sessions reattach. |

## Open Validation Items

These items must be validated as the **first tasks** of the implementation plan, before downstream code lands. Misjudging them invalidates the design.

1. **Real exit-output format for Claude Code and Codex.** The default regexes in this spec are written from convention, not from observed output. The first implementation task is to actually run a real `claude` and `codex` to a clean exit (`/exit` or `Ctrl-D`), capture the literal terminating output, and commit fixtures (`Tests/MuxyTests/Fixtures/agent-exit-claude.txt`, `agent-exit-codex.txt`). Update `AgentKind.defaultResumeRegex` to match the observed format.
2. **Real CLI acceptance of resume invocations.** Verify that:
   - `claude --dangerously-skip-permissions --resume <id>` actually loads the previous session (the `.appendArgs` strategy is correct).
   - `codex resume <id>` actually loads the previous session and that the loss of preset top-level flags (`--disable apps --dangerously-bypass-approvals-and-sandbox`) does not break expected behavior (the `.replaceWithCaptured` strategy is acceptable).
   - If `.replaceWithCaptured` proves wrong for Codex, fall back to a per-kind resume command template (e.g. `"codex resume {id} --some-flag"` configured in code).
3. **Claude Code `Ctrl-C` exit semantics.** Observe whether the actual binary requires one or two `Ctrl-C` presses to exit, and whether it prints the resume hint on the first interrupt or only after confirmation. The tiered timeout described in the UI section assumes worst case (two presses); adjust if the real behavior differs.
4. **`tmux capture-pane` against wrapped or very long lines.** Validate that a resume hint printed across two visual rows (because of pane width) survives `-N -S -200` capture and matches the regex. If wrap is an issue, increase `-S` or move to capturing pane history with `-J` (joins wrapped lines).

These validations must produce concrete artifacts (fixtures, recorded behavior notes) checked in alongside the implementation, not informal observations.

## Out of Scope

- `metadataOnly` runtime support for reload. Banner and menu hide themselves there.
- `.terminal` panes.
- Real-time binary upgrade detection (FSEvents). Lazy on focus is sufficient for this iteration.
- Preset editor UI for `resumeCommandRegex`.
- Reload keyboard shortcut. Add later if the menu / banner UX is too slow.
- Surfacing "preset changed" as a distinct trigger.
- OpenCode resume detection (regex stays `nil` until upstream behavior is examined).
