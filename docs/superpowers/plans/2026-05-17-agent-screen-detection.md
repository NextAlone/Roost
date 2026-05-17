# Agent Screen Heuristic Detection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 hostd daemon 中通过 `tmux capture-pane` 周期性采样 agent 终端屏幕内容，用模式匹配推断 agent 工作状态 (idle/working/blocked)，作为 hook 的 fallback 检测层。

**Architecture:** 扩展现有 daemon request-response 模式——App 端 Timer 周期调用 daemon 的 `detectAgentActivity` 操作，daemon 执行 `tmux capture-pane` + per-agent 模式匹配后返回状态。状态变化时 app 调用 `updateAgentActivity(sourceType: "screenHeuristic")`。

**Tech Stack:** Swift 6.0, RoostHostdCore (daemon), tmux capture-pane, pattern matching

**Scope:** Claude Code + Codex only. hostdOwnedProcess 模式 only. metadataOnly 模式不覆盖.

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `RoostHostdCore/AgentDetection/AgentDetectorProtocol.swift` | Create | 检测器协议 + AgentDetectionResult 类型 |
| `RoostHostdCore/AgentDetection/ClaudeCodeDetector.swift` | Create | Claude Code 屏幕模式匹配 |
| `RoostHostdCore/AgentDetection/CodexDetector.swift` | Create | Codex 屏幕模式匹配 |
| `RoostHostdCore/AgentDetection/AgentDetectionStateMachine.swift` | Create | 去抖逻辑 (Claude 1.2s sticky) |
| `RoostHostdCore/HostdAttachSocketMessages.swift` | Modify | 新增 `.detectAgentActivity` operation + 请求/响应类型 |
| `RoostHostdCore/HostdProcessRegistry.swift` | Modify | 新增 `detectAgentActivity(id:)` 方法 |
| `RoostHostdCore/HostdDaemonSocketServer.swift` | Modify | 新增 operation case 处理 |
| `RoostHostdCore/HostdXPCProtocol.swift` | Modify | 新增协议方法 |
| `RoostHostdCore/HostdXPCMessages.swift` | Modify | 新增请求/响应类型 |
| `RoostHostdXPCService/HostdXPCService.swift` | Modify | 新增方法实现 (hostdOwnedProcess 路径) |
| `Muxy/Services/Hostd/HostdXPCTransport` (protocol) | Modify | 新增 transport 方法声明 |
| `Muxy/Services/Hostd/HostdSocketTransport.swift` | Modify | 新增 socket transport 实现 |
| `Muxy/Services/Hostd/XPCHostdClient.swift` | Modify | 新增 NSXPC transport + client 实现 |
| `Muxy/Services/Hostd/RoostHostdClient.swift` | Modify | 新增 client 协议方法 + 默认实现 |
| `Muxy/Services/AgentScreenDetectionService.swift` | Create | App 端周期检测服务 |
| `Muxy/Models/AppState.swift` | Modify | 集成检测服务 (启动/停止/回调) |
| `Tests/MuxyTests/Services/AgentScreenDetectorTests.swift` | Create | 检测器单元测试 |

---

### Task 1: AgentDetector Protocol + Types

**Files:**
- Create: `RoostHostdCore/AgentDetection/AgentDetectorProtocol.swift`

- [ ] **Step 1: Write AgentDetectorProtocol.swift**

```swift
import Foundation

public enum AgentDetectionState: String, Sendable, Codable, Equatable {
    case idle
    case working
    case blocked
    case unknown

    public var label: String {
        switch self {
        case .idle: "idle"
        case .working: "working"
        case .blocked: "blocked"
        case .unknown: "unknown"
        }
    }
}

public struct AgentDetectionResult: Sendable, Codable, Equatable {
    public let state: AgentDetectionState
    public let agentLabel: String?

    public init(state: AgentDetectionState, agentLabel: String?) {
        self.state = state
        self.agentLabel = agentLabel
    }
}

public protocol AgentDetector: Sendable {
    var agentLabel: String { get }
    func detect(screenContent: String) -> AgentDetectionState
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
swift build --target RoostHostdCore
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(hostd): add AgentDetector protocol and detection state types"
```

---

### Task 2: ClaudeCodeDetector

**Files:**
- Create: `RoostHostdCore/AgentDetection/ClaudeCodeDetector.swift`

- [ ] **Step 1: Write ClaudeCodeDetector.swift**

```swift
import Foundation

public struct ClaudeCodeDetector: AgentDetector {
    public let agentLabel = "claude"

    public init() {}

    public func detect(screenContent: String) -> AgentDetectionState {
        let lower = screenContent.lowercased()

        if screenContent.contains("\u{2315} Search") {
            return .idle
        }
        if lower.contains("ctrl+r to toggle") {
            return .idle
        }

        if hasBlockedPrompt(screenContent, lower) {
            return .blocked
        }

        let above = contentAbovePromptBox(screenContent)
        let aboveLower = above.lowercased()
        if aboveLower.contains("esc to interrupt") || aboveLower.contains("ctrl+c to interrupt") {
            return .working
        }
        if hasSpinnerActivity(above) {
            return .working
        }

        return .idle
    }

    private func hasBlockedPrompt(_ content: String, _ lower: String) -> Bool {
        if lower.contains("do you want to proceed?")
            || lower.contains("would you like to proceed?")
            || lower.contains("waiting for permission")
            || lower.contains("do you want to allow this connection?")
            || lower.contains("tab to amend")
            || lower.contains("ctrl+e to explain")
            || lower.contains("chat about this")
            || lower.contains("review your answers")
            || lower.contains("skip interview and plan immediately") {
            return true
        }
        if hasConfirmationPrompt(lower) {
            return true
        }
        if hasSelectionPrompt(content) && hasYesNoChoice(content) {
            return true
        }
        return false
    }

    private func hasConfirmationPrompt(_ lower: String) -> Bool {
        guard let pos = lower.range(of: "do you want")?.lowerBound
            ?? lower.range(of: "would you like")?.lowerBound else {
            return false
        }
        let after = lower[pos...]
        return after.contains("yes") || after.contains("\u{276F}")
    }

    private func hasSelectionPrompt(_ content: String) -> Bool {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\u{276F}"),
               trimmed.contains(where: { $0.isNumber }),
               trimmed.contains(".") {
                return true
            }
        }
        return false
    }

    private func hasYesNoChoice(_ content: String) -> Bool {
        content.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{276F}"))
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            return trimmed == "yes" || trimmed == "no"
                || trimmed.hasPrefix("1. yes") || trimmed.hasPrefix("2. no")
                || trimmed.hasPrefix("yes, and ") || trimmed.hasPrefix("no, and tell claude")
        }
    }

    private func hasSpinnerActivity(_ content: String) -> Bool {
        let spinnerChars = Set("\u{00B7}\u{2731}\u{2732}\u{2733}\u{2734}\u{2735}\u{2736}\u{2737}\u{2738}\u{2739}\u{273A}\u{273B}\u{273C}\u{273D}\u{273E}\u{273F}\u{2740}\u{2741}\u{2742}\u{2743}\u{2747}\u{2748}\u{2749}\u{274A}\u{274B}\u{2722}\u{2723}\u{2724}\u{2725}\u{2726}\u{2727}\u{2728}\u{229B}\u{2295}\u{2299}\u{25C9}\u{25CE}\u{2042}\u{2055}\u{203B}\u{235F}\u{2606}\u{2605}")
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first else { continue }
            if spinnerChars.contains(first) {
                let rest = trimmed.dropFirst()
                if rest.hasPrefix(" "),
                   rest.contains("\u{2026}"),
                   rest.contains(where: { $0.isLetter || $0.isNumber }) {
                    return true
                }
            }
        }
        return false
    }

    private func contentAbovePromptBox(_ content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var borderCount = 0
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "\u{2500}" }) {
                borderCount += 1
                if borderCount == 2 {
                    return lines[0..<i].joined(separator: "\n")
                }
            }
        }
        return content
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
swift build --target RoostHostdCore
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(hostd): add Claude Code screen detector"
```

---

### Task 3: CodexDetector

**Files:**
- Create: `RoostHostdCore/AgentDetection/CodexDetector.swift`

- [ ] **Step 1: Write CodexDetector.swift**

```swift
import Foundation

public struct CodexDetector: AgentDetector {
    public let agentLabel = "codex"

    public init() {}

    public func detect(screenContent: String) -> AgentDetectionState {
        let lower = screenContent.lowercased()

        if lower.contains("press enter to confirm or esc to cancel")
            || lower.contains("enter to submit answer")
            || lower.contains("allow command?")
            || lower.contains("[y/n]")
            || lower.contains("yes (y)") {
            return .blocked
        }
        if hasConfirmationPrompt(lower) {
            return .blocked
        }

        if hasInterruptPattern(lower) || hasWorkingHeader(screenContent) {
            return .working
        }

        return .idle
    }

    private func hasConfirmationPrompt(_ lower: String) -> Bool {
        guard let pos = lower.range(of: "do you want")?.lowerBound
            ?? lower.range(of: "would you like")?.lowerBound else {
            return false
        }
        return lower[pos...].contains("yes") || lower[pos...].contains("\u{276F}")
    }

    private func hasInterruptPattern(_ lower: String) -> Bool {
        lower.contains("esc to interrupt")
            || lower.contains("ctrl+c to interrupt")
            || (lower.contains("esc") && lower.contains("interrupt"))
    }

    private func hasWorkingHeader(_ content: String) -> Bool {
        content.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("\u{2022}") && trimmed.contains("Working (")
        }
    }
}
```

- [ ] **Step 2: Build to verify compilation**

```bash
swift build --target RoostHostdCore
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(hostd): add Codex screen detector"
```

---

### Task 4: AgentDetectionStateMachine (Debounce)

**Files:**
- Create: `RoostHostdCore/AgentDetection/AgentDetectionStateMachine.swift`

- [ ] **Step 1: Write AgentDetectionStateMachine.swift**

```swift
import Foundation

public struct AgentDetectionStateMachine: Sendable {
    public var currentState: AgentDetectionState = .unknown
    private var consecutiveCount: Int = 0
    private var lastClaudeWorkingAt: Date?

    private static let claudeWorkingHold: TimeInterval = 1.2
    private static let confirmationThreshold: Int = 2

    public init() {}

    public mutating func observe(rawState: AgentDetectionState, agentLabel: String?, now: Date = Date()) -> AgentDetectionState? {
        let stabilized = stabilize(rawState, agentLabel: agentLabel, now: now)
        if stabilized == currentState {
            consecutiveCount = 0
            return nil
        }
        if stabilized != rawState && rawState != currentState {
            consecutiveCount += 1
            if consecutiveCount < Self.confirmationThreshold {
                return nil
            }
        }
        consecutiveCount = 0
        let previous = currentState
        currentState = stabilized
        if stabilized != previous {
            return stabilized
        }
        return nil
    }

    public mutating func reset() {
        currentState = .unknown
        consecutiveCount = 0
        lastClaudeWorkingAt = nil
    }

    private mutating func stabilize(_ raw: AgentDetectionState, agentLabel: String?, now: Date) -> AgentDetectionState {
        guard agentLabel == "claude" else { return raw }
        switch raw {
        case .working:
            lastClaudeWorkingAt = now
            return .working
        case .blocked:
            return .blocked
        case .idle where currentState == .working:
            if let lastWorking = lastClaudeWorkingAt,
               now.timeIntervalSince(lastWorking) < Self.claudeWorkingHold {
                return .working
            }
            return .idle
        default:
            return raw
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
swift build --target RoostHostdCore
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(hostd): add agent detection state machine with debounce"
```

---

### Task 5: Add detectAgentActivity Operation + Types

**Files:**
- Modify: `RoostHostdCore/HostdAttachSocketMessages.swift` — add operation case + request/response types

- [ ] **Step 1: Add operation case to HostdAttachSocketOperation enum (after `.sendTmuxKeys`)**

```swift
case detectAgentActivity
```

- [ ] **Step 2: Add request type at end of file (before `HostdDaemonSocket`)**

```swift
public struct HostdDetectAgentActivityRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let agentLabel: String

    public init(id: UUID, agentLabel: String) {
        self.id = id
        self.agentLabel = agentLabel
    }
}
```

Response type 复用 Task 1 的 `AgentDetectionResult`，无需额外定义。

- [ ] **Step 3: Build**

```bash
swift build --target RoostHostdCore
```

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(hostd): add detectAgentActivity socket operation and types"
```

---

### Task 6: Add detectAgentActivity to HostdProcessRegistry

**Files:**
- Modify: `RoostHostdCore/HostdProcessRegistry.swift`

- [ ] **Step 1: Add import at top**

```swift
import AgentDetection
```

(Wait, AgentDetection is a subdirectory within RoostHostdCore, not a separate module. Types defined in it are already accessible. No import needed beyond Foundation.)

- [ ] **Step 2: Add `detectAgentActivity` method to HostdProcessRegistry (after `waitForSessionExit`)**

Find the `waitForSessionExit` method in `HostdProcessRegistry`. Add this new method after it:

```swift
func detectAgentActivity(id: UUID, agentLabel: String) async throws -> AgentDetectionResult {
    let sessionName = HostdTmuxSessionName.name(for: id)
    guard await tmux.hasSession(named: sessionName) else {
        return AgentDetectionResult(state: .unknown, agentLabel: nil)
    }
    let screenContent = await tmux.captureLastTail(sessionName: sessionName, lines: 40) ?? ""
    let detector: any AgentDetector = switch agentLabel {
    case "claude": ClaudeCodeDetector()
    case "codex": CodexDetector()
    default: return AgentDetectionResult(state: .unknown, agentLabel: nil)
    }
    let state = detector.detect(screenContent: screenContent)
    return AgentDetectionResult(state: state, agentLabel: detector.agentLabel)
}
```

- [ ] **Step 3: Build**

```bash
swift build --target RoostHostdCore
```

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(hostd): add detectAgentActivity to HostdProcessRegistry"
```

---

### Task 7: Handle in HostdDaemonSocketServer

**Files:**
- Modify: `RoostHostdCore/HostdDaemonSocketServer.swift`

- [ ] **Step 1: Add case to the switch in `handle()` (after `.sendTmuxKeys`)**

```swift
case .detectAgentActivity:
    let request = try HostdXPCCodec.decode(HostdDetectAgentActivityRequest.self, from: request.payload)
    let response = try await registry.detectAgentActivity(id: request.id, agentLabel: request.agentLabel)
    payload = try HostdXPCCodec.success(response)
```

- [ ] **Step 2: Build**

```bash
swift build --target RoostHostdCore
```

- [ ] **Step 3: Commit**

```bash
jj commit -m "feat(hostd): handle detectAgentActivity in daemon socket server"
```

---

### Task 8: Add to XPC Protocol + Service

**Files:**
- Modify: `RoostHostdCore/HostdXPCProtocol.swift`
- Modify: `RoostHostdXPCService/HostdXPCService.swift`
- Modify: `RoostHostdCore/HostdXPCMessages.swift`

- [ ] **Step 1: Add protocol method to HostdXPCProtocol (after `sendTmuxKeys`)**

```swift
func detectAgentActivity(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
```

- [ ] **Step 2: Add request/response types to HostdXPCMessages.swift (at end, before `HostdXPCCodec`)**

```swift
public struct HostdDetectAgentActivityRequest: Sendable, Codable, Equatable {
    public let id: UUID
    public let agentLabel: String

    public init(id: UUID, agentLabel: String) {
        self.id = id
        self.agentLabel = agentLabel
    }
}
```

(`HostdDetectAgentActivityResponse` uses `AgentDetectionState` which is already in RoostHostdCore. No additional type needed since `AgentDetectionResult` already conforms to `Codable`.)

Actually, `HostdDetectAgentActivityRequest` is already defined in `HostdAttachSocketMessages.swift`. We need it accessible from both. Since both files are in the same module (`RoostHostdCore`), we only define it once. The XPC protocol needs a separate request wrapper — but since the Data-encoded approach means the actual struct is encoded/decoded by the caller, we can reuse the same struct.

So Step 2 is not needed — `HostdDetectAgentActivityRequest` is already in `HostdAttachSocketMessages.swift` (same module). The protocol just passes `Data`.

- [ ] **Step 3: Add implementation to HostdXPCService.swift (after `sendTmuxKeys`)**

```swift
func detectAgentActivity(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
    if runtime.ownership == .hostdOwnedProcess {
        respondRegistry(reply) { registry in
            let request = try HostdXPCCodec.decode(HostdDetectAgentActivityRequest.self, from: request)
            let response = try await registry.detectAgentActivity(id: request.id, agentLabel: request.agentLabel)
            return try HostdXPCCodec.success(response)
        }
        return
    }
    rejectRuntimeControl("detect agent activity", request: request, as: HostdDetectAgentActivityRequest.self, reply: reply)
}
```

- [ ] **Step 4: Build**

```bash
swift build
```

- [ ] **Step 5: Commit**

```bash
jj commit -m "feat(hostd): add detectAgentActivity to XPC protocol and service"
```

---

### Task 9: Add Client Transport Layer

**Files:**
- Modify: `Muxy/Services/Hostd/HostdSocketTransport.swift` (protocol extension)
- Modify: `Muxy/Services/Hostd/XPCHostdClient.swift` (HostdXPCTransport protocol + NSXPC + XPCHostdClient)
- Modify: `Muxy/Services/Hostd/RoostHostdClient.swift` (protocol + default impl)

- [ ] **Step 1: Add transport method to HostdXPCTransport protocol in XPCHostdClient.swift (after `sendTmuxKeys`)**

In `XPCHostdClient.swift`, the `HostdXPCTransport` protocol:

```swift
func detectAgentActivity(_ request: Data) async throws -> Data
```

- [ ] **Step 2: Add NSXPCHostdTransport implementation (after `sendTmuxKeys`)**

```swift
func detectAgentActivity(_ request: Data) async throws -> Data {
    try await call { proxy, reply in
        proxy.detectAgentActivity(request, reply: reply)
    }
}
```

- [ ] **Step 3: Add HostdSocketTransport implementation (after `sendTmuxKeys`)**

```swift
func detectAgentActivity(_ request: Data) async throws -> Data {
    try await call(.detectAgentActivity, payload: request)
}
```

- [ ] **Step 4: Add to RoostHostdClient protocol (after `sendTmuxKeys`)**

```swift
func detectAgentActivity(id: UUID, agentLabel: String) async throws -> AgentDetectionResult
```

- [ ] **Step 5: Add default implementation in RoostHostdClient extension (after `sendTmuxKeys`)**

```swift
func detectAgentActivity(id: UUID, agentLabel: String) async throws -> AgentDetectionResult {
    let error = await unsupportedRuntimeControl("detect agent activity")
    throw error
}
```

- [ ] **Step 6: Add XPCHostdClient implementation (after `sendTmuxKeys`)**

```swift
func detectAgentActivity(id: UUID, agentLabel: String) async throws -> AgentDetectionResult {
    let request = try HostdXPCCodec.encode(HostdDetectAgentActivityRequest(id: id, agentLabel: agentLabel))
    let response = try await withRequestTimeout("detect agent activity") {
        try await transport.detectAgentActivity(request)
    }
    return try HostdXPCCodec.decodeReply(AgentDetectionResult.self, from: response)
}
```

Note: `AgentDetectionResult` is defined in `RoostHostdCore`, which `XPCHostdClient` already imports.

- [ ] **Step 7: Build**

```bash
swift build
```

- [ ] **Step 8: Commit**

```bash
jj commit -m "feat(hostd): add detectAgentActivity to client transport layer"
```

---

### Task 10: App-Side Detection Service

**Files:**
- Create: `Muxy/Services/AgentScreenDetectionService.swift`

- [ ] **Step 1: Write AgentScreenDetectionService.swift**

```swift
import Foundation
import MuxyShared
import RoostHostdCore

@MainActor
final class AgentScreenDetectionService: Sendable {
    private weak var appState: AppState?
    private var pollTask: Task<Void, Never>?
    private let client: any RoostHostdClient
    private let pollInterval: TimeInterval

    init(
        appState: AppState,
        client: any RoostHostdClient,
        pollInterval: TimeInterval = 0.5
    ) {
        self.appState = appState
        self.client = client
        self.pollInterval = pollInterval
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task.detached { [weak self, pollInterval] in
            while !Task.isCancelled {
                await self?.pollAllPanes()
                try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollAllPanes() async {
        guard let appState else { return }
        let panes = appState.allAgentPanes
        for pane in panes {
            guard pane.hostdRuntimeOwnership == .hostdOwnedProcess else { continue }
            let agentLabel = pane.agentKind.detectionLabel
            guard !agentLabel.isEmpty else { continue }
            do {
                let result = try await client.detectAgentActivity(id: pane.sessionID, agentLabel: agentLabel)
                let activityState = mapToActivityState(result.state)
                if activityState != pane.activityState {
                    await appState.updateAgentActivity(
                        paneID: pane.id,
                        state: activityState,
                        sourceType: "screenHeuristic"
                    )
                }
            } catch {
                // daemon unavailable or session gone — skip this pane
            }
        }
    }

    private func mapToActivityState(_ state: AgentDetectionState) -> AgentActivityState {
        switch state {
        case .idle: .idle
        case .working: .running
        case .blocked: .awaiting
        case .unknown: .idle
        }
    }
}

extension AgentKind {
    var detectionLabel: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        default: ""
        }
    }
}
```

- [ ] **Step 2: Add `allAgentPanes` computed property to AppState**

In `AppState.swift`, add:

```swift
var allAgentPanes: [TerminalPaneState] {
    var result: [TerminalPaneState] = []
    for (_, root) in workspaceRoots {
        for pane in root.allPanes where pane.agentKind != .terminal {
            result.append(pane)
        }
    }
    return result
}
```

This depends on helper computed properties in existing model files.

In `Muxy/Models/SplitNode.swift`, add:

```swift
var allPanes: [TerminalPaneState] {
    switch self {
    case .tabArea(let area):
        return area.tabs.compactMap { $0.content.pane }
    case .split(let branch):
        return branch.first.allPanes + branch.second.allPanes
    }
}
```

In `Muxy/Models/TerminalTab.swift`, add to `Content` enum:

```swift
var pane: TerminalPaneState? {
    if case .terminal(let state) = self { return state }
    return nil
}
```

- [ ] **Step 3: Build**

```bash
swift build
```

- [ ] **Step 4: Commit**

```bash
jj commit -m "feat(agent): add app-side screen detection polling service"
```

---

### Task 11: Wire into AppState Lifecycle

**Files:**
- Modify: `Muxy/Models/AppState.swift`

- [ ] **Step 1: Add property to AppState**

```swift
var screenDetectionService: AgentScreenDetectionService?
```

- [ ] **Step 2: Start service when hostd mode activates**

Find where hostd mode is initialized in AppState (or in the hostd client initialization path). Add:

```swift
func startScreenDetection(client: any RoostHostdClient) {
    let service = AgentScreenDetectionService(appState: self, client: client)
    screenDetectionService = service
    service.start()
}
```

- [ ] **Step 3: Stop service on teardown**

```swift
func stopScreenDetection() {
    screenDetectionService?.stop()
    screenDetectionService = nil
}
```

- [ ] **Step 4: Wire start/stop into existing hostd lifecycle**

Find where `RoostHostdClient` is first resolved and call `startScreenDetection`. Find where hostd is shut down and call `stopScreenDetection`.

- [ ] **Step 5: Build and verify**

```bash
swift build
```

- [ ] **Step 6: Commit**

```bash
jj commit -m "feat(agent): wire screen detection service into AppState lifecycle"
```

---

### Task 12: Unit Tests

**Files:**
- Create: `Tests/MuxyTests/Services/AgentScreenDetectorTests.swift`

- [ ] **Step 1: Write Claude Code detection tests**

```swift
import Testing
@testable import RoostHostdCore

struct ClaudeCodeDetectorTests {
    let detector = ClaudeCodeDetector()

    @Test func idleAtPrompt() {
        let screen = "Task complete.\n─────────────\n❯ \n─────────────"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func idleAtSearch() {
        let screen = "⌕ Search…\nsome content"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func idleAtSettingsMenu() {
        let screen = "Theme\nChoose the text style\n\n❯ 1. Dark mode ✔\n 2. Light mode\n\nEnter to select · Esc to cancel"
        #expect(detector.detect(screenContent: screen) == .idle)
    }

    @Test func workingEscToInterrupt() {
        let screen = "Reading file src/main.rs\nesc to interrupt\n─────────\n❯ \n─────────"
        #expect(detector.detect(screenContent: screen) == .working)
    }

    @Test func workingSpinner() {
        let screen = "✽ Tempering…\n─────────\n❯ \n─────────"
        #expect(detector.detect(screenContent: screen) == .working)
    }

    @Test func blockedDoYouWant() {
        let screen = "Do you want to run this command?\n\nYes No"
        #expect(detector.detect(screenContent: screen) == .blocked)
    }

    @Test func blockedSelectionPrompt() {
        let screen = "Do you want to proceed?\n❯ 1. Yes\n 2. No\n\nEsc to cancel · Tab to amend"
        #expect(detector.detect(screenContent: screen) == .blocked)
    }

    @Test func blockedWaitingForPermission() {
        let screen = "waiting for permission\nto run: rm -rf /tmp/test"
        #expect(detector.detect(screenContent: screen) == .blocked)
    }

    @Test func ctrlRToggleReturnsIdle() {
        let screen = "ctrl+r to toggle\n─────────\n❯ \n─────────"
        #expect(detector.detect(screenContent: screen) == .idle)
    }
}
```

- [ ] **Step 2: Write Codex detection tests**

```swift
struct CodexDetectorTests {
    let detector = CodexDetector()

    @Test func idleAtPrompt() {
        #expect(detector.detect(screenContent: "❯ ") == .idle)
    }

    @Test func workingEscToInterrupt() {
        #expect(detector.detect(screenContent: "generating code\nesc to interrupt") == .working)
    }

    @Test func workingHeader() {
        #expect(detector.detect(screenContent: "• Working (0s • esc…") == .working)
    }

    @Test func blockedConfirm() {
        #expect(detector.detect(screenContent: "press enter to confirm or esc to cancel") == .blocked)
    }

    @Test func blockedAllowCommand() {
        #expect(detector.detect(screenContent: "allow command?\n[y/n]") == .blocked)
    }

    @Test func blockedSubmitAnswer() {
        #expect(detector.detect(screenContent: "enter to submit answer\nesc to interrupt") == .blocked)
    }
}
```

- [ ] **Step 3: Write state machine tests**

```swift
struct AgentDetectionStateMachineTests {
    @Test func ignoresSingleFlicker() {
        var sm = AgentDetectionStateMachine()
        sm.observe(rawState: .working, agentLabel: "claude") // initial
        let result = sm.observe(rawState: .idle, agentLabel: "claude") // 1st flicker
        #expect(result == nil)
    }

    @Test func confirmsAfterTwoConsecutive() {
        var sm = AgentDetectionStateMachine()
        sm.observe(rawState: .working, agentLabel: "claude") // initial
        sm.observe(rawState: .idle, agentLabel: "claude") // 1st different
        let result = sm.observe(rawState: .idle, agentLabel: "claude") // 2nd confirm
        #expect(result == .idle)
    }

    @Test func claudeWorkingSticky() {
        var sm = AgentDetectionStateMachine()
        let now = Date()
        _ = sm.observe(rawState: .working, agentLabel: "claude", now: now)
        let result = sm.observe(rawState: .idle, agentLabel: "claude", now: now + 0.4)
        #expect(result == nil) // should stay working within 1.2s
    }

    @Test func claudeTransitionsAfterHoldExpires() {
        var sm = AgentDetectionStateMachine()
        let now = Date()
        _ = sm.observe(rawState: .working, agentLabel: "claude", now: now)
        _ = sm.observe(rawState: .idle, agentLabel: "claude", now: now + 1.3)
        let result = sm.observe(rawState: .idle, agentLabel: "claude", now: now + 1.3)
        #expect(result == .idle)
    }

    @Test func nonClaudeNoSticky() {
        var sm = AgentDetectionStateMachine()
        let now = Date()
        _ = sm.observe(rawState: .working, agentLabel: "codex", now: now)
        _ = sm.observe(rawState: .idle, agentLabel: "codex", now: now + 0.1)
        let result = sm.observe(rawState: .idle, agentLabel: "codex", now: now + 0.1)
        #expect(result == .idle)
    }
}
```

- [ ] **Step 4: Run tests**

```bash
swift test --filter AgentScreenDetectorTests
```

Expected: 16 tests pass.

- [ ] **Step 5: Commit**

```bash
jj commit -m "test(agent): add screen detector unit tests"
```

---

### Task 13: Manual Verification

- [ ] **Step 1: Build full app with hostd daemon**

```bash
swift build
```

- [ ] **Step 2: Launch app in hostdOwnedProcess mode, open a Claude Code agent pane**

- [ ] **Step 3: Verify state transitions in agent activity badge**

Test scenarios:
1. Start Claude Code → should show IDLE on launch
2. Send a prompt → should transition to RUNNING (spinner detected)
3. Wait for Claude to ask permission → should show WAIT (blocked detected)
4. Answer prompt → should return to RUNNING then IDLE on completion

- [ ] **Step 4: Repeat with Codex agent pane**

- [ ] **Step 5: Check logs for `sourceType: "screenHeuristic"` in AgentActivityEvent entries**

---

### Task 14: Run Full Test Suite

- [ ] **Step 1: Run all tests**

```bash
swift test
```

All existing tests must pass.

- [ ] **Step 2: Run linter**

```bash
scripts/checks.sh --fix
```

No new warnings or errors.

- [ ] **Step 3: Final commit if any lint fixes were applied**

```bash
jj commit -m "chore: apply lint fixes for agent screen detection"
```
