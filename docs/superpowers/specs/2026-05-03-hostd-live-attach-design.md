# Hostd Live Attach Design

## Goal

Make hostd-owned agent sessions behave like normal Ghostty terminals after the Roost UI closes and reopens. Output must render through the full terminal emulator, and input must use the same keyboard, IME, paste, mouse, resize, and shortcut handling as app-owned terminals.

The current SwiftUI text renderer path is a temporary diagnostic bridge. It proves that hostd can own a PTY, but it should not become the production terminal attach path.

## Background

Roost now has a hostd-owned mode that launches an agent process inside a PTY outside the main app window. The original XPC service proved the PTY ownership model, but macOS still ties an app-bundled XPC service to the app lifecycle. The durable path therefore uses a standalone `roost-hostd-daemon` process as the PTY owner and connects to it through a private Unix socket.

That design is insufficient for coding agents because Codex and similar tools are terminal UI applications. They rely on VT control sequences, cursor movement, erase operations, alternate screen behavior, bracketed paste, terminal modes, resize, signal behavior, and rich keyboard input. Reimplementing this in SwiftUI would duplicate Ghostty poorly and create a second terminal stack.

The durable design should match the proven pattern used by terminal multiplexers and persistent terminal products:

- A background owner process holds the PTY and process lifecycle.
- A foreground client attaches to that session.
- A complete terminal emulator renders the byte stream and handles local input.

References:

- tmux keeps sessions as collections of pseudo terminals managed by a server and lets clients attach later: https://man7.org/linux/man-pages/man1/tmux.1.html
- VS Code persistent terminals use process reconnection and revive rather than plain text replay: https://code.visualstudio.com/docs/terminal/advanced
- WezTerm multiplexing lets the GUI attach to mux domains that own panes, tabs, scrollback, and process state: https://wezterm.org/multiplexing.html
- xterm.js uses headless terminal state plus serialization for reconnection scenarios: https://github.com/xtermjs/xterm.js
- Ghostty's terminal control support belongs in the terminal emulator / VT layer, not in Roost UI code: https://ghostty.org/docs/vt

## Decision

Use an attach helper that runs inside a normal Ghostty surface.

Roost will launch `roost-hostd-attach --session <id>` as the command for hostd-owned panes. From Ghostty's perspective, this is a normal terminal command. From hostd's perspective, it is an attached client for an existing PTY session.

This keeps `GhosttyTerminalNSView` as the only production terminal renderer and input frontend. The helper bridges Ghostty's local terminal process to the hostd session.

## Non-Goals

- Do not keep expanding `HostdTerminalScreenBuffer` into a custom terminal emulator.
- Do not duplicate `GhosttyTerminalNSView` input handling in `HostdOwnedTerminalInputBridge`.
- Do not expose the hostd PTY file descriptor directly to the app until GhosttyKit has a supported adoption API.
- Do not require users to run tmux, screen, or an external multiplexer inside their agent sessions.

## Architecture

```text
GhosttyTerminalNSView
  runs command: roost-hostd-attach --session <session-id>
      stdin  -> helper -> daemon socket -> hostd -> agent PTY master
      stdout <- helper <- daemon socket <- hostd <- agent PTY master
```

### Hostd

`roost-hostd-daemon` hosts `HostdProcessRegistry` and remains the owner of agent PTYs. It opens the PTY, spawns the agent command, tracks process lifecycle, and keeps running after the Roost app exits.

The registry should stop using "read and consume directly from UI" as the main model. Instead each live session gets an internal output pump:

1. Read continuously from PTY master.
2. Append bytes to a bounded in-memory ring buffer with monotonically increasing sequence offsets.
3. Feed the same bytes into a headless terminal snapshot store.
4. Fan out bytes to attached clients.
5. Mark the session exited when the process exits and the PTY reaches EOF.

This prevents a detached or hidden UI from leaving the PTY unread until the child process blocks on a full PTY buffer.

### Attach Helper

`roost-hostd-attach` is a small executable shipped inside the app bundle.

Responsibilities:

- Resolve the hostd daemon socket endpoint.
- Attach to the requested session.
- Put its own controlling terminal into raw mode.
- Forward stdin bytes to hostd as input chunks.
- Request one terminal snapshot frame, write it to stdout, then read live hostd output chunks and write them unchanged to stdout.
- Forward terminal resize changes to hostd.
- Restore local terminal mode on exit.
- Release the hostd attach on clean exit.

The helper should not parse VT sequences or reinterpret keys. Ghostty handles the local terminal side; hostd owns the remote PTY side.

### App UI

For `hostdOwnedProcess` terminal panes, `TerminalPane` should mount the normal `TerminalBridge`, not `HostdOwnedTerminalView`.

The terminal command should be generated by `TerminalPaneEnvironment`:

```text
<bundle>/Contents/MacOS/roost-hostd-attach --session <uuid>
```

The pane still uses the same tab model, same focused pane logic, same search affordances where supported, and the same agent status badges. The only special behavior is the command being an attach client rather than the original agent command.

## Protocol Design

Current methods can remain for metadata and transition tests, but the live attach path needs a sequence-based stream API.

Suggested shared messages:

```swift
struct HostdAttachStreamRequest: Codable, Sendable {
    let id: UUID
    let afterSequence: UInt64?
    let mode: HostdOutputStreamReadMode
    let terminal: HostdAttachTerminal
}

enum HostdOutputStreamReadMode: String, Codable, Sendable {
    case raw
    case terminalSnapshot
}

struct HostdAttachTerminal: Codable, Sendable {
    let columns: UInt16
    let rows: UInt16
}

struct HostdOutputChunk: Codable, Sendable {
    let sequence: UInt64
    let data: Data
}

struct HostdReadStreamResponse: Codable, Sendable {
    let chunks: [HostdOutputChunk]
    let nextSequence: UInt64
    let sessionState: SessionState
}
```

The attach helper's first read uses `mode = .terminalSnapshot`. Hostd serializes the current visible terminal state into a bounded VT repaint frame and returns `nextSequence` set to the raw output sequence covered by that snapshot. Later reads use `mode = .raw` and `afterSequence = snapshot.nextSequence`, so the helper streams only live bytes after the snapshot boundary. A stale raw sequence older than the retained ring buffer should return the oldest retained sequence plus an explicit truncation flag so diagnostic consumers can continue instead of failing.

Input remains byte-oriented:

```swift
writeSessionInput(id: UUID, data: Data)
resizeSession(id: UUID, columns: UInt16, rows: UInt16)
sendSessionSignal(id: UUID, signal: HostdSessionSignal)
```

Ctrl-C should normally arrive as raw byte `0x03` from the helper because its local tty is in raw mode. Explicit signal forwarding remains useful for UI actions.

## Ring Buffer

Each session should retain bounded output independent of attached clients.

Requirements:

- Store bytes, not decoded strings.
- Track absolute byte sequence offsets.
- Drop oldest bytes when the limit is exceeded.
- Support reading from a known sequence.
- Support waiting until bytes are available or timeout expires.
- Keep final output after process exit until the session is deleted or pruned.

The first implementation can be in memory only. Persisted scrollback can be a later feature if needed.

## Terminal Snapshot

Each session keeps a SwiftTerm-backed headless terminal model beside the raw byte ring. The model is not a production UI renderer; it exists to produce an attach-time repaint frame with the current visible cells, attributes, alternate-screen state, and cursor position. Snapshot size must be bounded by terminal dimensions rather than retained byte history.

## Terminal Modes

The helper must configure its local tty so Ghostty is not fighting the shell line discipline:

- Disable canonical input.
- Disable local echo.
- Disable local signal generation when forwarding raw Ctrl-C as input.
- Preserve and restore the original `termios`.
- Handle EOF and daemon failure by restoring terminal state before exiting.

This is the same class of work that SSH and terminal multiplexers do for interactive attach clients.

## Lifecycle

### New Agent

1. App requests hostd to create a session with the agent command and launch environment.
2. Hostd opens PTY, starts the output pump, records the session as running.
3. App creates a terminal pane whose command is the attach helper for that session.
4. Ghostty launches the helper; the helper attaches and streams.

### App Close

1. Ghostty surface exits and terminates the helper process.
2. Helper releases the attach if possible.
3. Hostd keeps the PTY and output pump alive.
4. The agent process continues running.

### App Reopen

1. App lists live hostd sessions.
2. Existing workspace snapshot panes map to session IDs.
3. Each visible hostd pane mounts normal `TerminalBridge` with the attach helper command.
4. Helper receives a terminal snapshot frame and then live output after the snapshot sequence.

### Agent Exit

1. Hostd detects process exit.
2. Hostd keeps final output available for history.
3. Helper drains final output, exits with a clear status line, and lets the pane show an exited state.

## Error Handling

- Session not found: helper prints a concise actionable message and exits non-zero.
- Daemon unavailable: helper prints that hostd is unavailable and exits non-zero.
- Ring buffer truncation: raw diagnostic readers continue from oldest retained data and may show truncation explicitly. Normal attach starts from a terminal snapshot boundary.
- Input write failure: helper exits after printing the hostd error.
- Resize failure: helper reports once and continues; later resize attempts may recover.

Errors should not expose internal stack traces or sensitive environment values.

## Testing

### Unit Tests

- Ring buffer appends, truncates, and reads from sequence boundaries.
- Hostd output pump drains PTY output when no client is attached.
- Multiple attach readers can read without stealing bytes from each other.
- Stale sequence returns a truncation marker and a valid restart point.
- Helper command construction uses the bundled helper path and session ID.

### Integration Tests

- Launch a hostd session running `/bin/cat`, attach helper, type input, observe echoed output.
- Launch a command that emits `\r`, `CSI K`, alternate screen, and UTF-8 split chunks; verify Ghostty renders through the normal terminal path.
- Close helper while the process keeps outputting; verify hostd keeps draining and later attach receives recent output.
- Resize the attached terminal and verify the session PTY receives the new dimensions.

### Manual Acceptance

- Start Codex, close Roost, reopen Roost, and attach to the same Codex session.
- Type normal text, Enter, Ctrl-C, paste multiline input, and Chinese or emoji text.
- Confirm Codex TUI output is not duplicated, garbled, or rendered as raw escape text.
- Confirm app-owned terminals still behave exactly as before.

## Migration Plan

1. Keep the current hostd-owned text UI only as a temporary fallback while the attach helper is introduced.
2. Add hostd output pump and ring buffer behind the existing registry.
3. Add attach stream protocol, daemon socket adapter, and compatibility XPC adapter methods.
4. Add `roost-hostd-attach` executable target.
5. Route hostd-owned panes through `TerminalBridge` using the helper command.
6. Remove `HostdOwnedTerminalInputBridge` and the custom live output renderer from production paths.
7. Retain small tests for UTF-8 and VT examples only as regression coverage for the ring/stream boundary, not as a renderer contract.

## Impact Scope

| Area | Impact |
| --- | --- |
| `RoostHostdCore` | Add output pump, ring buffer, sequence-based stream reads, and attach lifecycle accounting. |
| `RoostHostdDaemon` | Run the durable hostd process that owns PTYs after the app exits. |
| `RoostHostdXPCService` | Keep metadata-only compatibility and development fallback behavior. |
| `Muxy/Services/Hostd` | Add daemon launch, daemon socket transport, helper command resolution, and phase out UI-owned output model. |
| `Muxy/Views/Terminal` | Route hostd-owned panes back through `TerminalBridge`. |
| `Package.swift` | Add attach helper and daemon executable targets and package them in release builds. |
| `scripts/build-release.sh` | Bundle and sign the helper and daemon executables. |
| Tests | Add registry, stream, helper command, and release packaging coverage. |

## Risks

- Socket streaming through polling may add latency. Mitigation: start with timeout reads and upgrade to push callbacks only if needed.
- A helper process per attached pane is extra overhead. This is acceptable for the first production-quality path because it reuses Ghostty correctly.
- The helper needs careful termios cleanup. Tests should cover normal exit and signal exit where feasible.
- Ring buffer memory must be bounded per session to avoid runaway output.
- Search over hostd-owned terminals depends on Ghostty's live surface state, not hostd persisted scrollback.

## Exit Criteria

- Hostd-owned Codex panes render through normal Ghostty surfaces.
- There is no production SwiftUI VT parser for live hostd terminal output.
- There is no separate production key-mapping bridge for hostd terminal input.
- Closing the app does not kill hostd-owned agent processes.
- Reopening the app attaches to live sessions without `sessionNotFound` for running sessions.
- `scripts/checks.sh --fix` passes.
