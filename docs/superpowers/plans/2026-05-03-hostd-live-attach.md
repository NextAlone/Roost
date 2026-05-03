# Hostd Live Attach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the temporary hostd-owned SwiftUI terminal renderer with a Ghostty-backed attach flow so hostd-owned agent sessions render and accept input like normal Roost terminals.

**Architecture:** a standalone `roost-hostd-daemon` owns the long-lived PTY and drains output into a bounded byte ring buffer. Roost opens a normal Ghostty surface that runs `roost-hostd-attach --session <id>`; the helper bridges its local stdin/stdout to hostd over the daemon Unix socket. The app no longer has a second production terminal input or VT rendering stack.

**Tech Stack:** Swift 6, SwiftUI/AppKit, libghostty via `GhosttyKit`, Foundation XPC, Darwin PTY/termios APIs, SQLite-backed `SessionStore`, `swift-testing`, `jj`.

---

## File Structure

- Create `RoostHostdCore/HostdOutputRingBuffer.swift`: byte ring buffer with absolute sequence offsets.
- Modify `RoostHostdCore/HostdProcessRegistry.swift`: add per-session output pump, sequence reads, and non-stealing attach semantics.
- Modify `RoostHostdCore/HostdXPCMessages.swift`: add stream request/response DTOs.
- Modify `RoostHostdCore/HostdXPCProtocol.swift`: add XPC method for sequence stream reads.
- Modify `RoostHostdXPCService/HostdXPCService.swift`: expose stream reads in hostd-owned mode.
- Create `RoostHostdDaemon/main.swift`: run the durable daemon process that owns hostd sessions.
- Create `RoostHostdCore/HostdDaemonSocketServer.swift`: expose hostd operations over the daemon Unix socket.
- Create `Muxy/Services/Hostd/HostdDaemonLauncher.swift`: launch and connect to the daemon on demand.
- Create `RoostHostdAttach/main.swift`: command-line attach helper.
- Create `RoostHostdAttach/HostdAttachTerminal.swift`: termios raw mode and resize helpers.
- Create `RoostHostdAttach/HostdAttachClient.swift`: minimal daemon socket client for helper.
- Modify `Package.swift`: add `RoostHostdAttach` executable target and product.
- Modify `Package.swift`: add `RoostHostdDaemon` executable target and product.
- Modify `scripts/build-release.sh`: build, copy, and sign attach helper and daemon into `Roost.app/Contents/MacOS/`.
- Modify `Muxy/Views/Terminal/TerminalPaneEnvironment.swift`: build attach helper command for hostd-owned sessions.
- Modify `Muxy/Views/Terminal/TerminalPane.swift`: route hostd-owned panes through `TerminalBridge`.
- Delete `Muxy/Views/Terminal/HostdOwnedTerminalInputBridge.swift`: remove production duplicate input bridge.
- Delete or demote `Muxy/Services/Hostd/HostdOwnedTerminalOutputModel.swift`: remove production live renderer model after app path uses helper.
- Delete or demote `Muxy/Services/Hostd/HostdTerminalScreenBuffer.swift`: remove custom VT screen buffer from production path.
- Modify tests under `Tests/MuxyTests/Hostd/`: add ring, registry, XPC stream, and helper command coverage; remove tests that assert SwiftUI live rendering behavior.
- Modify `docs/architecture.md`: document hostd live attach architecture.

## Task 1: Byte Ring Buffer

**Files:**
- Create: `RoostHostdCore/HostdOutputRingBuffer.swift`
- Test: `Tests/MuxyTests/Hostd/HostdOutputRingBufferTests.swift`

- [ ] **Step 1: Write failing ring buffer tests**

Create `Tests/MuxyTests/Hostd/HostdOutputRingBufferTests.swift`:

```swift
import Foundation
import RoostHostdCore
import Testing

@Suite("HostdOutputRingBuffer")
struct HostdOutputRingBufferTests {
    @Test("append assigns monotonic sequences")
    func appendAssignsMonotonicSequences() {
        var buffer = HostdOutputRingBuffer(limit: 16)

        buffer.append(Data("abc".utf8))
        buffer.append(Data("def".utf8))

        #expect(buffer.read(after: nil) == HostdOutputRead(
            chunks: [HostdOutputChunk(sequence: 0, data: Data("abcdef".utf8))],
            nextSequence: 6,
            truncated: false
        ))
    }

    @Test("read from sequence returns suffix")
    func readFromSequenceReturnsSuffix() {
        var buffer = HostdOutputRingBuffer(limit: 16)
        buffer.append(Data("abcdef".utf8))

        #expect(buffer.read(after: 3) == HostdOutputRead(
            chunks: [HostdOutputChunk(sequence: 3, data: Data("def".utf8))],
            nextSequence: 6,
            truncated: false
        ))
    }

    @Test("stale sequence resumes at retained boundary")
    func staleSequenceResumesAtRetainedBoundary() {
        var buffer = HostdOutputRingBuffer(limit: 4)
        buffer.append(Data("abcdef".utf8))

        #expect(buffer.read(after: 0) == HostdOutputRead(
            chunks: [HostdOutputChunk(sequence: 2, data: Data("cdef".utf8))],
            nextSequence: 6,
            truncated: true
        ))
    }
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter HostdOutputRingBufferTests
```

Expected: build fails because `HostdOutputRingBuffer`, `HostdOutputRead`, and `HostdOutputChunk` do not exist.

- [ ] **Step 3: Implement ring buffer**

Create `RoostHostdCore/HostdOutputRingBuffer.swift`:

```swift
import Foundation

public struct HostdOutputChunk: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let data: Data

    public init(sequence: UInt64, data: Data) {
        self.sequence = sequence
        self.data = data
    }
}

public struct HostdOutputRead: Equatable, Sendable {
    public let chunks: [HostdOutputChunk]
    public let nextSequence: UInt64
    public let truncated: Bool

    public init(chunks: [HostdOutputChunk], nextSequence: UInt64, truncated: Bool) {
        self.chunks = chunks
        self.nextSequence = nextSequence
        self.truncated = truncated
    }
}

public struct HostdOutputRingBuffer: Sendable {
    private let limit: Int
    private var bytes = Data()
    private var startSequence: UInt64 = 0
    private var endSequence: UInt64 = 0

    public init(limit: Int) {
        self.limit = max(1, limit)
    }

    public mutating func append(_ data: Data) {
        guard !data.isEmpty else { return }
        bytes.append(data)
        endSequence += UInt64(data.count)
        trim()
    }

    public func read(after sequence: UInt64?) -> HostdOutputRead {
        let requested = sequence ?? startSequence
        let effective = max(requested, startSequence)
        let truncated = requested < startSequence
        guard effective < endSequence else {
            return HostdOutputRead(chunks: [], nextSequence: endSequence, truncated: truncated)
        }
        let offset = Int(effective - startSequence)
        return HostdOutputRead(
            chunks: [HostdOutputChunk(sequence: effective, data: bytes.suffix(from: offset))],
            nextSequence: endSequence,
            truncated: truncated
        )
    }

    private mutating func trim() {
        guard bytes.count > limit else { return }
        let dropCount = bytes.count - limit
        bytes.removeFirst(dropCount)
        startSequence += UInt64(dropCount)
    }
}
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
swift test --filter HostdOutputRingBufferTests
```

Expected: `HostdOutputRingBufferTests` passes.

- [ ] **Step 5: Commit**

Run:

```bash
jj commit -m "feat(hostd): add output ring buffer"
```

Expected: a new empty `@` is created and the ring buffer revision is described.

## Task 2: Hostd Output Pump and Sequence Reads

**Files:**
- Modify: `RoostHostdCore/HostdProcessRegistry.swift`
- Test: `Tests/MuxyTests/Hostd/HostdProcessRegistryTests.swift`

- [ ] **Step 1: Add failing registry stream tests**

Add tests to `Tests/MuxyTests/Hostd/HostdProcessRegistryTests.swift`:

```swift
@Test("output pump retains output before attach read")
func outputPumpRetainsOutputBeforeAttachRead() async throws {
    let registry = try await HostdProcessRegistry(databaseURL: temporaryDatabaseURL())
    let id = UUID()
    _ = try await registry.launchSession(HostdLaunchSessionRequest(
        id: id,
        projectID: UUID(),
        worktreeID: UUID(),
        workspacePath: FileManager.default.temporaryDirectory.path,
        agentKind: .terminal,
        command: "printf retained",
        environment: ["TERM": "xterm-256color"]
    ))

    let output = try await waitForHostdOutput(registry: registry, id: id, after: nil, contains: "retained")

    #expect(String(decoding: output.chunks.flatMap(\.data), as: UTF8.self).contains("retained"))
}

@Test("stream reads do not steal bytes from other clients")
func streamReadsDoNotStealBytesFromOtherClients() async throws {
    let registry = try await HostdProcessRegistry(databaseURL: temporaryDatabaseURL())
    let id = UUID()
    _ = try await registry.launchSession(HostdLaunchSessionRequest(
        id: id,
        projectID: UUID(),
        worktreeID: UUID(),
        workspacePath: FileManager.default.temporaryDirectory.path,
        agentKind: .terminal,
        command: "printf shared",
        environment: ["TERM": "xterm-256color"]
    ))

    let first = try await waitForHostdOutput(registry: registry, id: id, after: nil, contains: "shared")
    let second = try await registry.readSessionOutputStream(id: id, after: nil, timeout: 0)

    #expect(String(decoding: first.chunks.flatMap(\.data), as: UTF8.self).contains("shared"))
    #expect(String(decoding: second.chunks.flatMap(\.data), as: UTF8.self).contains("shared"))
}

private func waitForHostdOutput(
    registry: HostdProcessRegistry,
    id: UUID,
    after: UInt64?,
    contains needle: String
) async throws -> HostdOutputRead {
    for _ in 0 ..< 100 {
        let output = try await registry.readSessionOutputStream(id: id, after: after, timeout: 0.05)
        if String(decoding: output.chunks.flatMap(\.data), as: UTF8.self).contains(needle) {
            return output
        }
    }
    throw HostdProcessRegistryTestError.outputTimeout
}

private enum HostdProcessRegistryTestError: Error {
    case outputTimeout
}
```

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter 'HostdProcessRegistryTests/outputPumpRetainsOutputBeforeAttachRead|HostdProcessRegistryTests/streamReadsDoNotStealBytesFromOtherClients'
```

Expected: build fails because `readSessionOutputStream` does not exist.

- [ ] **Step 3: Add output pump state**

Modify `HostdPTYSession` in `RoostHostdCore/HostdProcessRegistry.swift` to own:

```swift
private let outputLock = NSLock()
private let outputCondition = NSCondition()
private var outputBuffer = HostdOutputRingBuffer(limit: 256 * 1024)
private var outputPumpStarted = false
```

Add a `startOutputPump()` method that reads from `masterFD` on a detached task, appends bytes to `outputBuffer`, and signals `outputCondition`.

Replace direct UI-driven destructive output reads with:

```swift
func readOutput(after sequence: UInt64?, timeout: TimeInterval) async throws -> HostdOutputRead {
    let deadline = Date().addingTimeInterval(max(0, timeout))
    while true {
        let read = outputLock.withLock {
            outputBuffer.read(after: sequence)
        }
        if !read.chunks.isEmpty || timeout <= 0 || !isRunning {
            return read
        }
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 { return read }
        try await Task.sleep(nanoseconds: UInt64(min(remaining, 0.02) * 1_000_000_000))
    }
}
```

Keep `writeInput`, `resize`, and signal behavior writing to the same PTY master FD.

- [ ] **Step 4: Expose registry stream method**

Add to `HostdProcessRegistry`:

```swift
public func readSessionOutputStream(id: UUID, after sequence: UInt64?, timeout: TimeInterval = 0) async throws -> HostdOutputRead {
    guard let session = sessions[id] else { throw HostdProcessRegistryError.sessionNotFound(id) }
    return try await session.readOutput(after: sequence, timeout: timeout)
}
```

Keep `readAvailableOutput` temporarily as a compatibility wrapper that reads from the current stream boundary only if tests still depend on it.

- [ ] **Step 5: Run tests and verify pass**

Run:

```bash
swift test --filter HostdProcessRegistryTests
```

Expected: registry tests pass, including existing input, resize, signal, and stale persisted session tests.

- [ ] **Step 6: Commit**

Run:

```bash
jj commit -m "feat(hostd): stream retained PTY output"
```

Expected: a new empty `@` is created.

## Task 3: XPC Stream Protocol

**Files:**
- Modify: `RoostHostdCore/HostdXPCMessages.swift`
- Modify: `RoostHostdCore/HostdXPCProtocol.swift`
- Modify: `RoostHostdXPCService/HostdXPCService.swift`
- Modify: `Muxy/Services/Hostd/XPCHostdClient.swift`
- Modify: `Muxy/Services/Hostd/RoostHostdClient.swift`
- Test: `Tests/MuxyTests/Hostd/HostdXPCCodecTests.swift`
- Test: `Tests/MuxyTests/Hostd/HostdXPCServiceRuntimeTests.swift`
- Test: `Tests/MuxyTests/Hostd/XPCHostdClientTests.swift`

- [ ] **Step 1: Write failing XPC codec test**

Add to `HostdXPCCodecTests`:

```swift
@Test("stream output request and response round trip")
func streamOutputRoundTrip() throws {
    let request = HostdReadSessionOutputStreamRequest(id: UUID(), afterSequence: 42, timeout: 0.25)
    let decodedRequest = try HostdXPCCodec.decode(HostdXPCCodec.encode(request), as: HostdReadSessionOutputStreamRequest.self)
    #expect(decodedRequest == request)

    let response = HostdReadSessionOutputStreamResponse(
        chunks: [HostdOutputChunk(sequence: 42, data: Data("x".utf8))],
        nextSequence: 43,
        truncated: false,
        state: .running
    )
    let decodedResponse = try HostdXPCCodec.decode(HostdXPCCodec.success(response), as: HostdReadSessionOutputStreamResponse.self)
    #expect(decodedResponse == response)
}
```

- [ ] **Step 2: Run codec test and verify failure**

Run:

```bash
swift test --filter 'HostdXPCCodecTests/streamOutputRoundTrip'
```

Expected: build fails because stream DTOs do not exist.

- [ ] **Step 3: Add DTOs**

Add to `RoostHostdCore/HostdXPCMessages.swift`:

```swift
public struct HostdReadSessionOutputStreamRequest: Codable, Equatable, Sendable {
    public let id: UUID
    public let afterSequence: UInt64?
    public let timeout: TimeInterval

    public init(id: UUID, afterSequence: UInt64?, timeout: TimeInterval) {
        self.id = id
        self.afterSequence = afterSequence
        self.timeout = timeout
    }
}

public struct HostdReadSessionOutputStreamResponse: Codable, Equatable, Sendable {
    public let chunks: [HostdOutputChunk]
    public let nextSequence: UInt64
    public let truncated: Bool
    public let state: SessionState

    public init(chunks: [HostdOutputChunk], nextSequence: UInt64, truncated: Bool, state: SessionState) {
        self.chunks = chunks
        self.nextSequence = nextSequence
        self.truncated = truncated
        self.state = state
    }
}
```

- [ ] **Step 4: Add protocol and client method**

Add `readSessionOutputStream(_ request: Data, reply: @escaping @Sendable (Data) -> Void)` to `HostdXPCProtocol`.

Add to `RoostHostdClient`:

```swift
func readSessionOutputStream(id: UUID, after sequence: UInt64?, timeout: TimeInterval) async throws -> HostdReadSessionOutputStreamResponse
```

Implement it in `XPCHostdClient` by encoding the request and decoding the response.

- [ ] **Step 5: Implement service endpoint**

Add to `RoostHostdXPCService/HostdXPCService.swift`:

```swift
func readSessionOutputStream(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
    guard runtime.ownership == .hostdOwnedProcess else {
        rejectRuntimeControl("read output stream", request: request, as: HostdReadSessionOutputStreamRequest.self, reply: reply)
        return
    }
    respond(reply) { registry in
        let request = try HostdXPCCodec.decode(request, as: HostdReadSessionOutputStreamRequest.self)
        let output = try await registry.readSessionOutputStream(
            id: request.id,
            after: request.afterSequence,
            timeout: request.timeout
        )
        return HostdReadSessionOutputStreamResponse(
            chunks: output.chunks,
            nextSequence: output.nextSequence,
            truncated: output.truncated,
            state: .running
        )
    }
}
```

If the session exits, return `.exited` after the registry exposes that state.

- [ ] **Step 6: Run hostd XPC tests**

Run:

```bash
swift test --filter 'HostdXPCCodecTests|HostdXPCServiceRuntimeTests|XPCHostdClientTests'
```

Expected: all XPC tests pass.

- [ ] **Step 7: Commit**

Run:

```bash
jj commit -m "feat(hostd): expose output stream over xpc"
```

Expected: a new empty `@` is created.

## Task 4: Attach Helper Executable

**Files:**
- Create: `RoostHostdAttach/main.swift`
- Create: `RoostHostdAttach/HostdAttachTerminal.swift`
- Create: `RoostHostdAttach/HostdAttachClient.swift`
- Modify: `Package.swift`
- Test: `Tests/MuxyTests/Hostd/HostdAttachCommandTests.swift`

- [ ] **Step 1: Add package target**

Modify `Package.swift` to add:

```swift
.executable(name: "roost-hostd-attach", targets: ["RoostHostdAttach"])
```

and:

```swift
.executableTarget(
    name: "RoostHostdAttach",
    dependencies: ["RoostHostdCore", "MuxyShared"],
    path: "RoostHostdAttach"
)
```

- [ ] **Step 2: Write helper terminal support**

Create `RoostHostdAttach/HostdAttachTerminal.swift`:

```swift
import Darwin
import Foundation

struct HostdAttachTerminal {
    private let inputFD: CInt
    private let outputFD: CInt
    private var original = termios()
    private var rawApplied = false

    init(inputFD: CInt = STDIN_FILENO, outputFD: CInt = STDOUT_FILENO) {
        self.inputFD = inputFD
        self.outputFD = outputFD
    }

    mutating func enterRawMode() throws {
        guard tcgetattr(inputFD, &original) == 0 else { throw HostdAttachTerminalError.termios(errno) }
        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_cflag |= tcflag_t(CS8)
        raw.c_cc.16 = 1
        raw.c_cc.17 = 0
        guard tcsetattr(inputFD, TCSAFLUSH, &raw) == 0 else { throw HostdAttachTerminalError.termios(errno) }
        rawApplied = true
    }

    mutating func restore() {
        guard rawApplied else { return }
        _ = tcsetattr(inputFD, TCSAFLUSH, &original)
        rawApplied = false
    }

    func size() -> (columns: UInt16, rows: UInt16)? {
        var value = winsize()
        guard ioctl(outputFD, TIOCGWINSZ, &value) == 0 else { return nil }
        guard value.ws_col > 0, value.ws_row > 0 else { return nil }
        return (value.ws_col, value.ws_row)
    }
}

enum HostdAttachTerminalError: Error {
    case termios(Int32)
}
```

Replace tuple index access if Swift rejects `raw.c_cc.16` syntax by adding a small helper around `withUnsafeMutableBytes(of: &raw.c_cc)`.

- [ ] **Step 3: Write helper daemon socket client**

Create `RoostHostdAttach/HostdAttachClient.swift` with a minimal Unix socket client that sends `HostdAttachSocketRequest` messages to `roost-hostd-daemon`. It should expose:

```swift
struct HostdAttachClient {
    func attach(id: UUID) async throws
    func release(id: UUID) async
    func read(id: UUID, after sequence: UInt64?, timeout: TimeInterval) async throws -> HostdReadSessionOutputStreamResponse
    func write(id: UUID, data: Data) async throws
    func resize(id: UUID, columns: UInt16, rows: UInt16) async throws
}
```

Use `HostdDaemonSocket.defaultSocketPath` and `HostdAttachSocketOperation` as the remote interface.

- [ ] **Step 4: Write helper main loop**

Create `RoostHostdAttach/main.swift`:

```swift
import Darwin
import Foundation
import RoostHostdCore

@main
struct RoostHostdAttachMain {
    static func main() async {
        do {
            let sessionID = try parseSessionID(arguments: CommandLine.arguments)
            var terminal = HostdAttachTerminal()
            try terminal.enterRawMode()
            defer { terminal.restore() }

            let client = HostdAttachClient()
            try await client.attach(id: sessionID)
            defer { Task { await client.release(id: sessionID) } }

            if let size = terminal.size() {
                try? await client.resize(id: sessionID, columns: size.columns, rows: size.rows)
            }

            await withTaskGroup(of: Void.self) { group in
                group.addTask { await pumpInput(sessionID: sessionID, client: client) }
                group.addTask { await pumpOutput(sessionID: sessionID, client: client) }
                await group.waitForAll()
            }
        } catch {
            FileHandle.standardError.write(Data("roost-hostd-attach: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}
```

Implement `pumpInput` as blocking reads from stdin in a detached task and `pumpOutput` as repeated stream reads writing raw `Data` to stdout.

- [ ] **Step 5: Build helper**

Run:

```bash
swift build --product roost-hostd-attach
```

Expected: helper builds.

- [ ] **Step 6: Commit**

Run:

```bash
jj commit -m "feat(hostd): add attach helper"
```

Expected: a new empty `@` is created.

## Task 5: Route Hostd-Owned Panes Through Ghostty

**Files:**
- Modify: `Muxy/Views/Terminal/TerminalPaneEnvironment.swift`
- Modify: `Muxy/Views/Terminal/TerminalPane.swift`
- Modify: `Muxy/Models/TerminalPaneState.swift` if a session ID helper is needed.
- Test: `Tests/MuxyTests/Terminal/TerminalPaneEnvironmentTests.swift`
- Test: `Tests/MuxyTests/Models/AgentTabCreationTests.swift`

- [ ] **Step 1: Write failing command construction test**

Add to `TerminalPaneEnvironmentTests`:

```swift
@Test("hostd owned panes run attach helper command")
func hostdOwnedPanesRunAttachHelperCommand() {
    let paneID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    let pane = TerminalPaneState(
        id: paneID,
        workingDirectory: "/tmp",
        title: "Codex",
        command: "codex",
        agentKind: .codex,
        hostdRuntimeOwnership: .hostdOwnedProcess
    )

    let environment = TerminalPaneEnvironment.build(
        pane: pane,
        appEnvironment: .testing,
        hostdClient: FakeHostdClient(runtimeOwnershipHint: .hostdOwnedProcess)
    )

    #expect(environment.command?.contains("roost-hostd-attach") == true)
    #expect(environment.command?.contains(paneID.uuidString) == true)
}
```

- [ ] **Step 2: Run test and verify failure**

Run:

```bash
swift test --filter 'TerminalPaneEnvironmentTests/hostdOwnedPanesRunAttachHelperCommand'
```

Expected: fails because hostd-owned panes still use the original agent command.

- [ ] **Step 3: Build attach command**

Update `TerminalPaneEnvironment.build` so hostd-owned panes use a shell-safe attach command:

```swift
let attachCommand = HostdAttachCommandBuilder.command(sessionID: pane.id)
```

Create a small builder in `Muxy/Services/Hostd/HostdAttachCommandBuilder.swift` if needed. It should resolve:

```swift
Bundle.main.executableURL?
    .deletingLastPathComponent()
    .appendingPathComponent("roost-hostd-attach")
```

Use `/usr/bin/env roost-hostd-attach` only for development builds where the bundled helper is absent.

- [ ] **Step 4: Route through `TerminalBridge`**

Modify `TerminalPane.body` so it always mounts `TerminalBridge` for terminal panes. Remove the `HostdOwnedTerminalView` branch from the production path.

- [ ] **Step 5: Run focused tests**

Run:

```bash
swift test --filter 'TerminalPaneEnvironmentTests|AgentTabCreationTests'
```

Expected: tests pass and hostd-owned agent tabs carry the attach helper command.

- [ ] **Step 6: Commit**

Run:

```bash
jj commit -m "feat(hostd): attach live sessions through ghostty"
```

Expected: a new empty `@` is created.

## Task 6: Remove Temporary Live Renderer and Input Bridge

**Files:**
- Delete: `Muxy/Views/Terminal/HostdOwnedTerminalInputBridge.swift`
- Delete or remove production references to: `Muxy/Services/Hostd/HostdOwnedTerminalOutputModel.swift`
- Delete or remove production references to: `Muxy/Services/Hostd/HostdTerminalScreenBuffer.swift`
- Modify: `Tests/MuxyTests/Hostd/HostdOwnedTerminalOutputModelTests.swift`
- Modify: `Tests/MuxyTests/Hostd/HostdOwnedTerminalInputEncoderTests.swift`

- [ ] **Step 1: Search for production references**

Run:

```bash
rg -n "HostdOwnedTerminal|HostdTerminalScreenBuffer|HostdOwnedTerminalInputBridge" Muxy RoostHostdCore RoostHostdXPCService Tests/MuxyTests
```

Expected: references are limited to files that will be deleted or rewritten.

- [ ] **Step 2: Remove renderer branch**

Delete the SwiftUI-only hostd terminal view and input bridge code from `TerminalPane.swift`. The pane should use only `TerminalBridge` for hostd-owned and app-owned terminal panes.

- [ ] **Step 3: Remove obsolete tests**

Delete tests asserting `HostdOwnedTerminalOutputModel` live rendering behavior. Keep any useful UTF-8 split coverage by moving it to stream/ring tests where bytes remain bytes.

- [ ] **Step 4: Run focused search**

Run:

```bash
rg -n "HostdOwnedTerminal|HostdTerminalScreenBuffer|HostdOwnedTerminalInputBridge" Muxy RoostHostdCore RoostHostdXPCService
```

Expected: no production references remain.

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --filter 'Hostd|TerminalPaneEnvironment|AgentTabCreationTests'
```

Expected: tests pass.

- [ ] **Step 6: Commit**

Run:

```bash
jj commit -m "refactor(hostd): remove temporary terminal renderer"
```

Expected: a new empty `@` is created.

## Task 7: Release Packaging

**Files:**
- Modify: `scripts/build-release.sh`
- Test: release build command

- [ ] **Step 1: Add helper copy/signing**

Update `scripts/build-release.sh` to copy:

```text
.build/<triple>/release/roost-hostd-attach
```

to:

```text
build/Roost.app/Contents/MacOS/roost-hostd-attach
```

Set executable permissions and sign it before signing the app bundle.

- [ ] **Step 2: Validate script syntax**

Run:

```bash
bash -n scripts/build-release.sh
```

Expected: no output and exit 0.

- [ ] **Step 3: Build release package**

Run:

```bash
build_number=$(date +%Y%m%d%H%M)
scripts/build-release.sh --arch arm64 --version 1.0.0 --zip --build-number "$build_number" --sign-identity -
```

Expected: `build/Roost.app`, `build/Roost-1.0.0-arm64.zip`, and `build/SHA256SUMS.txt` are produced.

- [ ] **Step 4: Verify helper is packaged**

Run:

```bash
test -x build/Roost.app/Contents/MacOS/roost-hostd-attach
codesign --verify --deep --strict build/Roost.app
```

Expected: both commands exit 0.

- [ ] **Step 5: Commit**

Run:

```bash
jj commit -m "chore(release): package hostd attach helper"
```

Expected: a new empty `@` is created.

## Task 8: Documentation and Final Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/superpowers/specs/2026-05-03-xpc-hostd-metadata-design.md`
- Verify: `docs/superpowers/specs/2026-05-03-hostd-live-attach-design.md`

- [ ] **Step 1: Update architecture docs**

Add a Hostd Live Attach section to `docs/architecture.md`:

```markdown
## Hostd Live Attach

In hostd-owned runtime mode, `roost-hostd-daemon` owns agent PTYs and keeps them alive outside the main app window. The app renders those sessions through normal `GhosttyTerminalNSView` surfaces by launching `roost-hostd-attach --session <id>` inside the pane. The helper bridges local stdin/stdout to hostd over the daemon socket while hostd drains the PTY into a bounded byte ring buffer.

Roost does not maintain a separate production VT renderer for hostd-owned panes.
```

- [ ] **Step 2: Update prior hostd metadata spec**

In `docs/superpowers/specs/2026-05-03-xpc-hostd-metadata-design.md`, replace the paragraph that says live Ghostty attach remains future UI work with a short note pointing to `2026-05-03-hostd-live-attach-design.md` as the active design.

- [ ] **Step 3: Run full checks**

Run:

```bash
scripts/checks.sh --fix
```

Expected: formatting, linting, and build pass.

- [ ] **Step 4: Run focused hostd tests**

Run:

```bash
swift test --filter 'Hostd|TerminalPaneEnvironment|AgentTabCreationTests'
```

Expected: hostd and terminal environment tests pass.

- [ ] **Step 5: Commit docs and cleanup**

Run:

```bash
jj commit -m "docs(hostd): document live attach architecture"
```

Expected: a new empty `@` is created.

## Manual Acceptance Checklist

- [ ] Start Roost with hostd-owned runtime enabled.
- [ ] Start a Codex agent in a workspace.
- [ ] Confirm the pane renders as a normal Ghostty terminal, not a SwiftUI text view.
- [ ] Type `ping` and Enter; confirm Codex receives input.
- [ ] Paste multiline text; confirm it arrives as one paste interaction.
- [ ] Type Chinese text and emoji; confirm input reaches Codex without mojibake.
- [ ] Press Ctrl-C; confirm Codex receives interrupt behavior.
- [ ] Resize the pane; confirm Codex TUI redraws.
- [ ] Close Roost while the agent is running.
- [ ] Reopen Roost and confirm the same live hostd session attaches.
- [ ] Confirm no `sessionNotFound` appears for a live hostd-owned session.
- [ ] Confirm app-owned terminals still launch and render normally.

## Plan Self-Review

- Spec coverage: output correctness maps to Tasks 1, 2, and 4; input correctness maps to Tasks 4 and 5; removal of custom renderer maps to Task 6; packaging maps to Task 7; docs and final verification map to Task 8.
- Placeholder scan: no TBD/TODO placeholders are used as implementation requirements.
- Type consistency: `HostdOutputChunk`, `HostdOutputRead`, `HostdReadSessionOutputStreamRequest`, and `HostdReadSessionOutputStreamResponse` are introduced before later tasks reference them.
- VCS consistency: all commit steps use `jj commit -m`, not `git`.
