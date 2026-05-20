# Agent 状态监控重构方案

## 背景

v1.4.6 ANR 日志（2026-05-20）显示：132 个线程中 80 个 `com.apple.root.utility-qos` dispatch 线程全部卡在 `HostdSocketIO.readAll`，打满软上限，导致主线程在退出时等待 735 秒。

根因分析识别出三个独立缺陷：

| 缺陷 | 位置 | 影响 |
|------|------|------|
| 传输层阻塞线程 | `HostdSocketTransport.call()` / `HostdDaemonSocketServer.readBlocking` | daemon 挂起时线程永不释放，ANR |
| 轮询架构 | `AgentScreenDetectionService` 每 500ms × N pane 串行 RPC | 40 pane 时每轮 ~2s，线性恶化 |
| `tmux capture-pane` fork/exec | `HostdTmuxController.run()` 每次检测两次子进程 | 与缺陷 1 同源，tmux 挂起同样泄漏线程 |

## 目标

- 消除传输层阻塞线程（解决 ANR）
- 消除 app 侧轮询（解决扩展性）
- 减少 `tmux capture-pane` fork/exec 调用（减少 tmux 负载）

## 不在本方案范围内

- `--output-format stream-json` 模式（破坏 terminal pane UI，需独立设计）
- tmux control mode 长连接（独立优化，可后续排期）

---

## 阶段 1：传输层修复（紧急，独立 PR）

**目标**：解决 ANR，不改业务逻辑。

### `RoostHostdCore/HostdSocketIO.swift`

新增 `readAllAsync`，基于 `DispatchSource.makeReadSource`，fd 无数据时不占线程：

```swift
public static func readAllAsync(from fd: CInt) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
        var accumulated = Data()
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &buffer, buffer.count)
            if n > 0 {
                accumulated.append(contentsOf: buffer[0..<n])
                if accumulated.count > maxMessageSize {
                    source.cancel()
                    continuation.resume(throwing: HostdSocketIOError.messageTooLarge)
                }
            } else if n == 0 {
                source.cancel()
                continuation.resume(returning: accumulated)
            } else if errno != EINTR {
                source.cancel()
                continuation.resume(throwing: HostdSocketIOError.readFailed(errnoMessage()))
            }
        }
        source.setCancelHandler { _ = source }  // 持有引用直到 cancel，防止 ARC 提前释放
        source.resume()
    }
}
```

### `RoostHostdCore/HostdDaemonSocketServer.swift`

`readBlocking` 改用 `readAllAsync`：

```swift
private static func readAsync(fd: CInt) async throws -> Data {
    try await HostdSocketIO.readAllAsync(from: fd)
}
```

`handleClient` 调用点替换为 `readAsync`。

### `Muxy/Services/Hostd/HostdSocketTransport.swift`

`call()` 加 Task 超时保险（10s），防止 `readAllAsync` 因极端情况挂起：

```swift
private func call(_ operation: HostdAttachSocketOperation, payload: Data = Data()) async throws -> Data {
    try await withThrowingTaskGroup(of: Data.self) { group in
        group.addTask { try await self.doCall(operation, payload: payload) }
        group.addTask {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            throw HostdSocketIOError.readFailed("timeout")
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

private func doCall(_ operation: HostdAttachSocketOperation, payload: Data) async throws -> Data {
    // 原 call() 实现移入此处
}
```

**协议版本**：不变（行为兼容）。

---

## 阶段 2：推送架构（主 PR，依赖阶段 1）

**目标**：daemon 内部检测，状态变化时推送，app 侧零轮询。

### 新增消息类型

**`RoostHostdCore/HostdAttachSocketMessages.swift`**：

```swift
// HostdAttachSocketOperation 新增
case subscribeAgentActivity

// 新增
public struct HostdSubscribeAgentActivityRequest: Codable, Sendable {
    public let subscriptions: [UUID: String]  // paneID → agentLabel
}

public struct HostdAgentActivityEvent: Codable, Sendable {
    public let paneID: UUID
    public let state: AgentDetectionState
    public let signal: AgentScreenSignal
    public let agentLabel: String
}
```

### `RoostHostdCore/HostdProcessRegistry.swift`

新增订阅管理和内部检测循环。subscriptions 存在 actor 状态里，每轮从最新状态读取（解决快照不更新问题）：

```swift
// actor 内新增状态
private var activitySubscribers: [UUID: AsyncStream<HostdAgentActivityEvent>.Continuation] = [:]
private var activityDetectionTask: Task<Void, Never>?
private var activeSubscriptions: [UUID: String] = [:]   // paneID → agentLabel，动态更新
private var lastPushedStates: [UUID: AgentDetectionState] = [:]

public func subscribeAgentActivity(
    subscriptions: [UUID: String]
) -> AsyncStream<HostdAgentActivityEvent> {
    activeSubscriptions.merge(subscriptions) { _, new in new }
    let subscriberID = UUID()
    let (stream, continuation) = AsyncStream<HostdAgentActivityEvent>.makeStream()
    activitySubscribers[subscriberID] = continuation
    continuation.onTermination = { [weak self] _ in
        Task { await self?.removeActivitySubscriber(subscriberID) }
    }
    if activityDetectionTask == nil {
        activityDetectionTask = Task { [weak self] in
            await self?.runDetectionLoop()
        }
    }
    return stream
}

private func removeActivitySubscriber(_ id: UUID) {
    activitySubscribers.removeValue(forKey: id)
    if activitySubscribers.isEmpty {
        activityDetectionTask?.cancel()
        activityDetectionTask = nil
        activeSubscriptions.removeAll()
        lastPushedStates.removeAll()
    }
}

private func runDetectionLoop() async {
    while !Task.isCancelled, !activitySubscribers.isEmpty {
        for (paneID, agentLabel) in activeSubscriptions {
            let result = await detectAgentActivity(id: paneID, agentLabel: agentLabel)
            guard result.state != .unknown else { continue }
            guard result.state != lastPushedStates[paneID] else { continue }
            lastPushedStates[paneID] = result.state
            let event = HostdAgentActivityEvent(
                paneID: paneID,
                state: result.state,
                signal: result.signal,
                agentLabel: agentLabel
            )
            for continuation in activitySubscribers.values {
                continuation.yield(event)
            }
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    activityDetectionTask = nil
}
```

pane 关闭时清理 `lastPushedStates`（在 `handleTmuxExit` 里）：

```swift
lastPushedStates.removeValue(forKey: id)
activeSubscriptions.removeValue(forKey: id)
```

### `RoostHostdCore/HostdDaemonSocketServer.swift`

`handleClient` 分支处理长连接：

```swift
private func handleClient(_ fd: CInt) async {
    do {
        let requestData = try await Self.readAsync(fd: fd)
        let request = try JSONDecoder().decode(HostdAttachSocketRequest.self, from: requestData)
        if request.operation == .subscribeAgentActivity {
            await handleSubscription(request, fd: fd)
            return
        }
        let response = try await handle(request)
        let responseData = try JSONEncoder().encode(response)
        try await Self.writeAsync(responseData, fd: fd)
    } catch {
        let response = HostdAttachSocketResponse(payload: HostdXPCCodec.failure(error.localizedDescription))
        if let data = try? JSONEncoder().encode(response) {
            try? await Self.writeAsync(data, fd: fd)
        }
    }
    close(fd)
}

private func handleSubscription(_ request: HostdAttachSocketRequest, fd: CInt) async {
    guard let req = try? JSONDecoder().decode(
        HostdSubscribeAgentActivityRequest.self, from: request.payload
    ) else { close(fd); return }

    let stream = await registry.subscribeAgentActivity(subscriptions: req.subscriptions)
    let encoder = JSONEncoder()
    for await event in stream {
        guard let data = try? encoder.encode(event) else { continue }
        var line = data
        line.append(0x0A)
        guard (try? HostdSocketIO.writeAll(line, to: fd)) != nil else { break }
    }
    close(fd)
}
```

### `Muxy/Services/Hostd/RoostHostdClient.swift`

协议新增方法：

```swift
func subscribeAgentActivity(
    subscriptions: [UUID: String]
) -> AsyncThrowingStream<HostdAgentActivityEvent, Error>
```

### `Muxy/Services/Hostd/HostdSocketTransport.swift`

新增订阅方法，`DispatchSource` 非阻塞逐行读取：

```swift
func subscribeAgentActivity(
    subscriptions: [UUID: String]
) -> AsyncThrowingStream<HostdAgentActivityEvent, Error> {
    let socketPath = self.socketPath
    return AsyncThrowingStream { continuation in
        Task {
            do {
                let payload = try JSONEncoder().encode(
                    HostdSubscribeAgentActivityRequest(subscriptions: subscriptions)
                )
                let fd = try HostdSocketIO.connect(path: socketPath)
                let req = HostdAttachSocketRequest(operation: .subscribeAgentActivity, payload: payload)
                try HostdSocketIO.writeAll(try JSONEncoder().encode(req), to: fd)
                shutdown(fd, SHUT_WR)

                var buf = Data()
                let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
                source.setEventHandler {
                    var tmp = [UInt8](repeating: 0, count: 4096)
                    let n = read(fd, &tmp, tmp.count)
                    if n <= 0 { source.cancel(); continuation.finish(); return }
                    buf.append(contentsOf: tmp[0..<n])
                    while let nl = buf.firstIndex(of: 0x0A) {
                        let line = Data(buf[buf.startIndex..<nl])
                        buf = Data(buf[buf.index(after: nl)...])
                        if let event = try? JSONDecoder().decode(HostdAgentActivityEvent.self, from: line) {
                            continuation.yield(event)
                        }
                    }
                }
                source.setCancelHandler { close(fd); _ = source }
                source.resume()
                continuation.onTermination = { _ in source.cancel() }
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
```

### `Muxy/Services/AgentScreenDetectionService.swift`

整体重写，删除 `reconcilers` 和 `pollPanes`：

```swift
@MainActor
final class AgentScreenDetectionService {
    private weak var appState: AppState?
    private let client: any RoostHostdClient
    private var subscriptionTask: Task<Void, Never>?

    init(appState: AppState, client: any RoostHostdClient) {
        self.appState = appState
        self.client = client
    }

    deinit { subscriptionTask?.cancel() }

    func start() {
        guard subscriptionTask == nil else { return }
        subscriptionTask = Task { [weak self] in await self?.runSubscription() }
    }

    func stop() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    private func runSubscription() async {
        var delay: UInt64 = 2_000_000_000
        while !Task.isCancelled {
            do {
                try await doSubscription()
                return
            } catch {
                try? await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, 30_000_000_000)
            }
        }
    }

    private func doSubscription() async throws {
        guard let appState else { return }
        let panes = appState.allAgentPanes.filter {
            $0.hostdRuntimeOwnership == .hostdOwnedProcess && !$0.agentKind.detectionLabel.isEmpty
        }
        guard !panes.isEmpty else { return }
        let subscriptions = Dictionary(uniqueKeysWithValues: panes.map { ($0.id, $0.agentKind.detectionLabel) })
        for try await event in client.subscribeAgentActivity(subscriptions: subscriptions) {
            guard !Task.isCancelled else { return }
            appState.updateAgentActivity(paneID: event.paneID, state: event.state, sourceType: "screenHeuristic")
        }
    }
}
```

### 协议版本

`HostdDaemonRuntimeIdentity.currentProtocolVersion` 10 → 11。

---

## 阶段 3：检测机制优化（独立 PR，可后续排期）

**目标**：用 `tmux display-message -p '#{pane_last_activity}'` 替代 `capture-pane`，减少 fork/exec 开销，同时保留屏幕内容分析作为精度补充。

`HostdTmuxControlling` 新增：

```swift
func paneLastActivity(sessionName: String) async -> Date?
```

实现：`tmux display-message -t <session>:0.0 -p '#{pane_last_activity}'`，返回 Unix 时间戳解析为 `Date`。

`detectAgentActivity` 改为：
1. 先用 `paneLastActivity` 判断输出空闲时长
2. 空闲 > 2s 时才调 `captureLastTail` 做精细检测
3. 活跃时直接返回 `.working`，跳过 `capture-pane`

这将 `capture-pane` 调用频率从每次检测必调降为仅在状态边界时调，大幅减少 fork/exec 次数。

---

## 文件改动汇总

| 文件 | 阶段 | 改动类型 |
|------|------|---------|
| `RoostHostdCore/HostdSocketIO.swift` | 1 | 新增 `readAllAsync` |
| `RoostHostdCore/HostdDaemonSocketServer.swift` | 1+2 | `readBlocking` 改非阻塞；新增长连接处理 |
| `Muxy/Services/Hostd/HostdSocketTransport.swift` | 1+2 | `call()` 加超时；新增 `subscribeAgentActivity` |
| `RoostHostdCore/HostdAttachSocketMessages.swift` | 2 | 新增 case + 两个结构体 |
| `RoostHostdCore/HostdProcessRegistry.swift` | 2+3 | 订阅管理 + 检测循环；pane 退出时清理状态 |
| `Muxy/Services/Hostd/RoostHostdClient.swift` | 2 | 协议新增方法 |
| `Muxy/Services/AgentScreenDetectionService.swift` | 2 | 整体重写 |
| `RoostHostdCore/HostdTmuxSession.swift` | 3 | 新增 `paneLastActivity` |
| `RoostHostdCore/HostdDaemonRuntimeIdentity.swift` | 2 | 版本 10 → 11 |

**不改动**：`AppState.swift`、`AgentDetection/` 目录、`RoostHostdDaemon/main.swift`。

---

## 风险与注意事项

**协议版本升级**：版本 11 触发旧 daemon 替换，替换期间订阅连接断开。`AgentScreenDetectionService` 的指数退避重连（2s→4s→…→30s）覆盖此场景。

**pane 增减**：`activeSubscriptions` 在 actor 内动态更新，新 pane 加入时调用方重新调 `subscribeAgentActivity` 传入完整列表即可合并。pane 关闭时 `handleTmuxExit` 清理对应条目。

**`writeAll` 阻塞**：`handleSubscription` 里的 `writeAll` 仍是同步写。当前事件量（40 pane × 状态变化频率低）不构成问题，后续可改为 `DispatchSource.makeWriteSource`。

**测试**：`runDetectionLoop` 和订阅机制需要补充单元测试，参考现有 `HostdDaemonSocketServerTests` 的模式。
