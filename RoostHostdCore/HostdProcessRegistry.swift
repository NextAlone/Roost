import Darwin
import Foundation
import MuxyShared
import os

public struct HostdLaunchSessionRequest: Sendable, Equatable {
    public let id: UUID
    public let projectID: UUID
    public let worktreeID: UUID
    public let workspacePath: String
    public let agentKind: AgentKind
    public let command: String
    public let createdAt: Date
    public let environment: [String: String]

    public init(
        id: UUID,
        projectID: UUID,
        worktreeID: UUID,
        workspacePath: String,
        agentKind: AgentKind,
        command: String,
        createdAt: Date = Date(),
        environment: [String: String] = [:]
    ) {
        self.id = id
        self.projectID = projectID
        self.worktreeID = worktreeID
        self.workspacePath = workspacePath
        self.agentKind = agentKind
        self.command = command
        self.createdAt = createdAt
        self.environment = environment
    }
}

public enum HostdProcessRegistryError: Error, LocalizedError, Equatable {
    case emptyCommand
    case sessionNotFound(UUID)
    case sessionNotAttached(UUID)
    case openPTYFailed(code: Int32, message: String)
    case configurePTYFailed(code: Int32, message: String)
    case spawnFailed(code: Int32, message: String)
    case readFailed(code: Int32, message: String)
    case writeFailed(code: Int32, message: String)
    case resizeFailed(code: Int32, message: String)
    case signalFailed(code: Int32, message: String)
    case terminateFailed(code: Int32, message: String)
    case tmuxUnavailable(message: String)
    case tmuxCommandFailed(operation: String, status: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyCommand:
            "Hostd cannot launch an empty command"
        case let .sessionNotFound(id):
            "Hostd session \(id.uuidString) is not running"
        case let .sessionNotAttached(id):
            "Hostd session \(id.uuidString) is not attached"
        case let .openPTYFailed(code, message):
            "Hostd failed to open PTY: \(message) (\(code))"
        case let .configurePTYFailed(code, message):
            "Hostd failed to configure PTY: \(message) (\(code))"
        case let .spawnFailed(code, message):
            "Hostd failed to spawn session process: \(message) (\(code))"
        case let .readFailed(code, message):
            "Hostd failed to read session output: \(message) (\(code))"
        case let .writeFailed(code, message):
            "Hostd failed to write session input: \(message) (\(code))"
        case let .resizeFailed(code, message):
            "Hostd failed to resize session PTY: \(message) (\(code))"
        case let .signalFailed(code, message):
            "Hostd failed to signal session process: \(message) (\(code))"
        case let .terminateFailed(code, message):
            "Hostd failed to terminate session process: \(message) (\(code))"
        case let .tmuxUnavailable(message):
            "Hostd tmux backend is unavailable: \(message)"
        case let .tmuxCommandFailed(operation, status, message):
            "Hostd tmux \(operation) failed: \(message) (\(status))"
        }
    }
}

public actor HostdProcessRegistry {
    private let store: SessionStore
    private let keepalive: any HostdProcessKeepalive
    private let tmux: any HostdTmuxControlling
    private var sessions: [UUID: HostdPTYSession] = [:]
    private var liveSessionIDs = Set<UUID>()
    private var tmuxAttachedClientCounts: [UUID: Int] = [:]
    private var pendingExitWaiters: [UUID: [WaiterEntry]] = [:]
    private var detectionStates: [UUID: AgentDetectionStateMachine] = [:]
    private var activitySubscribers: [UUID: AsyncStream<HostdAgentActivityEvent>.Continuation] = [:]
    private var activityDetectionTask: Task<Void, Never>?
    private var activeSubscriptions: [UUID: String] = [:]
    private var lastPushedStates: [UUID: AgentDetectionState] = [:]

    private struct WaiterEntry {
        let id: UUID
        let continuation: CheckedContinuation<HostdWaitForSessionExitResponse, Never>
    }

    init(
        store: SessionStore,
        keepalive: any HostdProcessKeepalive = NoopHostdProcessKeepalive(),
        tmux: any HostdTmuxControlling = HostdTmuxController()
    ) {
        self.store = store
        self.keepalive = keepalive
        self.tmux = tmux
    }

    public init(
        databaseURL: URL = HostdStorage.defaultDatabaseURL(),
        keepalive: any HostdProcessKeepalive = NoopHostdProcessKeepalive(),
        tmux: any HostdTmuxControlling = HostdTmuxController()
    ) async throws {
        self.store = try await SessionStore(url: databaseURL)
        self.keepalive = keepalive
        self.tmux = tmux
    }

    public func recoverRunningSessions() async throws {
        let running = try await store.listLive()
        for record in running {
            if record.agentKind == .terminal {
                try await store.update(id: record.id, lastState: .exited)
                continue
            }
            let sessionName = HostdTmuxSessionName.name(for: record.id)
            if await tmux.hasSession(named: sessionName) {
                startTmuxExitWatcher(id: record.id, sessionName: sessionName)
            } else {
                try await store.update(id: record.id, lastState: .exited)
            }
        }
    }

    public func launchSession(_ request: HostdLaunchSessionRequest) async throws -> HostdAttachSessionResponse {
        let command = request.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { throw HostdProcessRegistryError.emptyCommand }

        let record = SessionRecord(
            id: request.id,
            projectID: request.projectID,
            worktreeID: request.worktreeID,
            workspacePath: request.workspacePath,
            agentKind: request.agentKind,
            command: request.command,
            createdAt: request.createdAt,
            lastState: .running
        )
        if request.agentKind != .terminal {
            return try await launchTmuxSession(record: record, command: command, environment: request.environment)
        }
        let session = try HostdPTYSession.launch(record: record, command: command, environment: request.environment)
        do {
            try await store.record(record)
            sessions[request.id] = session
            liveSessionIDs.insert(request.id)
            keepalive.retainSession()
            startExitWatcher(id: request.id, session: session)
            return HostdAttachSessionResponse(record: record, ownership: .hostdOwnedProcess)
        } catch {
            try? session.terminate()
            throw error
        }
    }

    public func attachSession(id: UUID) async throws -> HostdAttachSessionResponse {
        if let session = sessions[id], session.isRunning {
            let count = session.attach()
            return HostdAttachSessionResponse(
                record: session.record,
                ownership: .hostdOwnedProcess,
                attachedClientCount: count
            )
        }
        if let record = try await storedRecord(id: id),
           record.agentKind != .terminal,
           await tmux.hasSession(named: HostdTmuxSessionName.name(for: id))
        {
            let count = (tmuxAttachedClientCounts[id] ?? 0) + 1
            tmuxAttachedClientCounts[id] = count
            return HostdAttachSessionResponse(
                record: record,
                ownership: .hostdOwnedProcess,
                attachedClientCount: count
            )
        }
        if sessions[id] != nil {
            try await markExitedIfKnown(id: id)
        }
        throw HostdProcessRegistryError.sessionNotFound(id)
    }

    public func releaseSession(id: UUID) async throws {
        if let session = sessions[id] {
            try session.release()
            return
        }
        guard let count = tmuxAttachedClientCounts[id], count > 0 else {
            throw HostdProcessRegistryError.sessionNotAttached(id)
        }
        let nextCount = count - 1
        if nextCount == 0 {
            tmuxAttachedClientCounts.removeValue(forKey: id)
        } else {
            tmuxAttachedClientCounts[id] = nextCount
        }
    }

    public func terminateSession(id: UUID) async throws {
        if let session = sessions.removeValue(forKey: id) {
            releaseKeepaliveIfLive(id: id)
            try session.terminate()
            try await store.update(id: id, lastState: .exited)
            return
        }
        guard let record = try await storedRecord(id: id), record.agentKind != .terminal else {
            throw HostdProcessRegistryError.sessionNotFound(id)
        }
        try await tmux.killSession(named: HostdTmuxSessionName.name(for: id))
        tmuxAttachedClientCounts.removeValue(forKey: id)
        try await store.update(id: id, lastState: .exited)
    }

    public func listLiveSessions() async throws -> [SessionRecord] {
        let persistedLive = try await store.listLive()
        var liveRecords: [SessionRecord] = []
        for record in persistedLive {
            if record.agentKind != .terminal {
                if await tmux.hasSession(named: HostdTmuxSessionName.name(for: record.id)) {
                    liveRecords.append(record)
                } else {
                    try await store.update(id: record.id, lastState: .exited)
                    tmuxAttachedClientCounts.removeValue(forKey: record.id)
                }
                continue
            }
            if let session = sessions[record.id], session.isRunning {
                liveRecords.append(record)
            } else {
                try await markExitedIfKnown(id: record.id)
            }
        }

        liveRecords.sort { $0.createdAt > $1.createdAt }
        return liveRecords
    }

    public func listAllSessions() async throws -> [SessionRecord] {
        try await store.list()
    }

    public func deleteSession(id: UUID) async throws {
        if let session = sessions.removeValue(forKey: id) {
            releaseKeepaliveIfLive(id: id)
            try session.terminate()
        } else if let record = try await storedRecord(id: id), record.agentKind != .terminal {
            try? await tmux.killSession(named: HostdTmuxSessionName.name(for: id))
            tmuxAttachedClientCounts.removeValue(forKey: id)
        }
        try await store.delete(id: id)
    }

    public func pruneExited() async throws {
        for (id, session) in sessions where !session.isRunning {
            sessions.removeValue(forKey: id)
            releaseKeepaliveIfLive(id: id)
        }
        try await store.pruneExited()
    }

    public func readAvailableOutput(id: UUID, timeout: TimeInterval = 0) async throws -> Data {
        guard let session = sessions[id] else { throw HostdProcessRegistryError.sessionNotFound(id) }
        return await session.readAvailableOutput(timeout: timeout)
    }

    public func readSessionOutputStream(
        id: UUID,
        after sequence: UInt64?,
        timeout: TimeInterval = 0,
        limit: Int? = nil,
        mode: HostdOutputStreamReadMode = .raw
    ) async throws -> HostdOutputRead {
        guard let session = sessions[id] else { throw HostdProcessRegistryError.sessionNotFound(id) }
        if mode == .terminalSnapshot {
            return session.readTerminalSnapshot()
        }
        let output = await session.readOutput(after: sequence, timeout: timeout, limit: limit)
        if output.streamEnded {
            try await markExitedIfKnown(id: id)
        }
        return output
    }

    public func writeSessionInput(id: UUID, data: Data) async throws {
        guard let session = sessions[id] else { throw HostdProcessRegistryError.sessionNotFound(id) }
        try await session.writeInput(data)
    }

    public func resizeSession(id: UUID, columns: UInt16, rows: UInt16) async throws {
        guard let session = sessions[id] else { throw HostdProcessRegistryError.sessionNotFound(id) }
        try session.resize(columns: columns, rows: rows)
    }

    public func sendSessionSignal(id: UUID, signal: HostdSessionSignal) async throws {
        guard let session = sessions[id] else { throw HostdProcessRegistryError.sessionNotFound(id) }
        try session.sendSignal(signal)
    }

    public func interruptTmuxSession(id: UUID) async throws {
        guard let record = try await storedRecord(id: id), record.agentKind != .terminal else {
            throw HostdProcessRegistryError.sessionNotFound(id)
        }
        try await tmux.sendKeys(sessionName: HostdTmuxSessionName.name(for: id), keys: "C-c")
    }

    public func sendTmuxKeys(id: UUID, keys: [String]) async throws {
        guard let record = try await storedRecord(id: id), record.agentKind != .terminal else {
            throw HostdProcessRegistryError.sessionNotFound(id)
        }
        let sessionName = HostdTmuxSessionName.name(for: id)
        for key in keys {
            try await tmux.sendKeys(sessionName: sessionName, keys: key)
        }
    }

    public func waitForSessionExit(
        id: UUID,
        timeoutMs: Int
    ) async -> HostdWaitForSessionExitResponse {
        if let record = try? await storedRecord(id: id), record.lastState == .exited {
            return HostdWaitForSessionExitResponse(lastTail: record.lastTail, didTimeout: false)
        }
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            pendingExitWaiters[id, default: []].append(WaiterEntry(id: waiterID, continuation: continuation))
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(max(timeoutMs, 0)) * 1_000_000)
                await self?.timeoutWaiter(sessionID: id, waiterID: waiterID)
            }
        }
    }

    public func detectAgentActivity(id: UUID, agentLabel: String) async -> AgentDetectionResult {
        let sessionName = HostdTmuxSessionName.name(for: id)
        guard await tmux.hasSession(named: sessionName) else {
            HostdLogger.log("[HostdDetection] NO SESSION: \(sessionName)")
            detectionStates.removeValue(forKey: id)
            return AgentDetectionResult(state: .unknown, agentLabel: nil)
        }
        guard let screenContent = await tmux.captureLastTail(sessionName: sessionName, lines: 40) else {
            HostdLogger.log("[HostdDetection] CAPTURE FAIL: \(sessionName)")
            detectionStates.removeValue(forKey: id)
            return AgentDetectionResult(state: .unknown, agentLabel: nil)
        }
        guard let detector = switch agentLabel {
        case "claude": ClaudeCodeDetector() as (any AgentDetector)?
        case "codex": CodexDetector() as (any AgentDetector)?
        default: nil as (any AgentDetector)?
        } else {
            HostdLogger.log("[HostdDetection] NO DETECTOR for: \(agentLabel)")
            return AgentDetectionResult(state: .unknown, agentLabel: nil)
        }
        let evidence = detector.detectEvidence(screenContent: screenContent)
        var stateMachine = detectionStates[id] ?? AgentDetectionStateMachine()
        guard let confirmedState = stateMachine.observe(rawState: evidence.state, agentLabel: agentLabel) else {
            detectionStates[id] = stateMachine
            if stateMachine.currentState != .unknown {
                HostdLogger
                    .log(
                        "[HostdDetection] pending \(agentLabel): raw=\(evidence.state.label) current=\(stateMachine.currentState.label) signal=\(evidence.signal.rawValue)"
                    )
            }
            return AgentDetectionResult(state: stateMachine.currentState, agentLabel: detector.agentLabel, signal: evidence.signal)
        }
        detectionStates[id] = stateMachine
        HostdLogger.log("[HostdDetection] CONFIRMED \(agentLabel): \(stateMachine.currentState.label) signal=\(evidence.signal.rawValue)")
        return AgentDetectionResult(state: confirmedState, agentLabel: detector.agentLabel, signal: evidence.signal)
    }

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
                let event = HostdAgentActivityEvent(paneID: paneID, detection: result)
                for continuation in activitySubscribers.values {
                    continuation.yield(event)
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        activityDetectionTask = nil
    }

    private func timeoutWaiter(sessionID: UUID, waiterID: UUID) {
        guard var waiters = pendingExitWaiters[sessionID],
              let idx = waiters.firstIndex(where: { $0.id == waiterID })
        else { return }
        let entry = waiters.remove(at: idx)
        if waiters.isEmpty {
            pendingExitWaiters.removeValue(forKey: sessionID)
        } else {
            pendingExitWaiters[sessionID] = waiters
        }
        entry.continuation.resume(returning: HostdWaitForSessionExitResponse(lastTail: nil, didTimeout: true))
    }

    private func resumeExitWaiters(sessionID: UUID, lastTail: String?) {
        guard let waiters = pendingExitWaiters.removeValue(forKey: sessionID) else { return }
        let response = HostdWaitForSessionExitResponse(lastTail: lastTail, didTimeout: false)
        for entry in waiters {
            entry.continuation.resume(returning: response)
        }
    }

    private func markExitedIfKnown(id: UUID) async throws {
        if sessions[id] != nil {
            releaseKeepaliveIfLive(id: id)
        }
        tmuxAttachedClientCounts.removeValue(forKey: id)
        try await store.update(id: id, lastState: .exited)
    }

    private func launchTmuxSession(
        record: SessionRecord,
        command: String,
        environment: [String: String]
    ) async throws -> HostdAttachSessionResponse {
        let sessionName = HostdTmuxSessionName.name(for: record.id)
        try await tmux.launch(
            sessionName: sessionName,
            workspacePath: record.workspacePath,
            command: command,
            environment: environment
        )
        do {
            try await store.record(record)
            startTmuxExitWatcher(id: record.id, sessionName: sessionName)
            return HostdAttachSessionResponse(record: record, ownership: .hostdOwnedProcess)
        } catch {
            try? await tmux.killSession(named: sessionName)
            throw error
        }
    }

    private func storedRecord(id: UUID) async throws -> SessionRecord? {
        try await store.list().first { $0.id == id }
    }

    private func startExitWatcher(id: UUID, session: HostdPTYSession) {
        Task.detached { [self] in
            while !Task.isCancelled {
                if !session.isRunning {
                    await markExitedFromExitWatcher(id: id)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func markExitedFromExitWatcher(id: UUID) async {
        guard sessions[id] != nil else { return }
        releaseKeepaliveIfLive(id: id)
        try? await store.update(id: id, lastState: .exited)
    }

    private static let paneDeadPollNanoseconds: UInt64 = 500_000_000

    static func runTmuxExitWatcherLoop(
        sessionName: String,
        tmux: any HostdTmuxControlling,
        pollNanoseconds: UInt64 = HostdProcessRegistry.paneDeadPollNanoseconds,
        onExit: @Sendable @escaping (_ lastTail: String?) -> Void
    ) async {
        while !Task.isCancelled {
            if await !(tmux.hasSession(named: sessionName)) {
                onExit(nil)
                return
            }
            if await tmux.isPaneDead(sessionName: sessionName) {
                let tail = await tmux.captureLastTail(sessionName: sessionName, lines: 200)
                onExit(tail)
                try? await tmux.killSession(named: sessionName)
                return
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }

    private func startTmuxExitWatcher(id: UUID, sessionName: String) {
        let tmux = self.tmux
        Task { [weak self] in
            let weakSelf = self
            await Self.runTmuxExitWatcherLoop(sessionName: sessionName, tmux: tmux) { lastTail in
                Task {
                    await weakSelf?.handleTmuxExit(id: id, sessionName: sessionName, lastTail: lastTail)
                }
            }
        }
    }

    private func handleTmuxExit(id: UUID, sessionName _: String, lastTail: String?) async {
        if let existing = try? await storedRecord(id: id) {
            let updated = SessionRecord(
                id: existing.id,
                projectID: existing.projectID,
                worktreeID: existing.worktreeID,
                workspacePath: existing.workspacePath,
                agentKind: existing.agentKind,
                command: existing.command,
                createdAt: existing.createdAt,
                lastState: .exited,
                lastTail: lastTail
            )
            try? await store.record(updated)
        }
        tmuxAttachedClientCounts.removeValue(forKey: id)
        activeSubscriptions.removeValue(forKey: id)
        lastPushedStates.removeValue(forKey: id)
        resumeExitWaiters(sessionID: id, lastTail: lastTail)
    }

    private func releaseKeepaliveIfLive(id: UUID) {
        guard liveSessionIDs.remove(id) != nil else { return }
        keepalive.releaseSession()
    }
}

private final class HostdPTYSession: @unchecked Sendable {
    private static let outputBufferLimit = 4 * 1024 * 1024
    private static let outputPollNanoseconds: UInt64 = 10_000_000
    private static let defaultRows: UInt16 = 40
    private static let defaultColumns: UInt16 = 120

    let record: SessionRecord
    private let pid: pid_t
    private let masterFD: CInt
    private let stateLock = NSLock()
    private let outputLock = NSLock()
    private var closed = false
    private var reaped = false
    private var attachedClientCount = 0
    private var outputBuffer = HostdOutputRingBuffer(limit: HostdPTYSession.outputBufferLimit)
    private let terminalSnapshot = HostdTerminalSnapshotStore(
        columns: HostdPTYSession.defaultColumns,
        rows: HostdPTYSession.defaultRows
    )
    private var compatibilityReadSequence: UInt64?
    private var outputPumpTask: Task<Void, Never>?

    init(record: SessionRecord, pid: pid_t, masterFD: CInt) {
        self.record = record
        self.pid = pid
        self.masterFD = masterFD
    }

    deinit {
        closeMaster()
    }

    var isRunning: Bool {
        stateLock.withLock {
            if reaped { return false }
            var status: CInt = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == 0 { return true }
            if result == pid || (result == -1 && errno == ECHILD) {
                reaped = true
                return false
            }
            return true
        }
    }

    func attach() -> Int {
        stateLock.withLock {
            attachedClientCount += 1
            return attachedClientCount
        }
    }

    func release() throws {
        let result = stateLock.withLock {
            guard attachedClientCount > 0 else { return false }
            attachedClientCount -= 1
            return true
        }
        guard result else {
            throw HostdProcessRegistryError.sessionNotAttached(record.id)
        }
    }

    static func launch(record: SessionRecord, command: String, environment: [String: String]) throws -> HostdPTYSession {
        var masterFD: CInt = -1
        var slaveFD: CInt = -1
        var slavePathBuffer = [CChar](repeating: 0, count: 1024)
        var initialSize = winsize(
            ws_row: HostdPTYSession.defaultRows,
            ws_col: HostdPTYSession.defaultColumns,
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        let openResult = slavePathBuffer.withUnsafeMutableBufferPointer { buffer in
            openpty(&masterFD, &slaveFD, buffer.baseAddress, nil, &initialSize)
        }
        guard openResult == 0 else {
            throw HostdProcessRegistryError.openPTYFailed(code: errno, message: errnoMessage())
        }
        let slavePathLength = slavePathBuffer.firstIndex(of: 0) ?? slavePathBuffer.count
        let slavePath = String(decoding: slavePathBuffer.prefix(slavePathLength).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        do {
            try configureNonBlocking(fd: masterFD)
            let pid = try spawn(
                command: command,
                cwd: record.workspacePath,
                environment: environment,
                masterFD: masterFD,
                slaveFD: slaveFD,
                slavePath: slavePath
            )
            close(slaveFD)
            let session = HostdPTYSession(record: record, pid: pid, masterFD: masterFD)
            session.startOutputPump()
            return session
        } catch {
            close(masterFD)
            close(slaveFD)
            throw error
        }
    }

    func readAvailableOutput(timeout: TimeInterval) async -> Data {
        let sequence = outputLock.withLock { compatibilityReadSequence }
        let output = await readOutput(after: sequence, timeout: timeout, limit: nil)
        outputLock.withLock {
            compatibilityReadSequence = output.nextSequence
        }
        return output.chunks.reduce(into: Data()) { data, chunk in
            data.append(chunk.data)
        }
    }

    func readOutput(after sequence: UInt64?, timeout: TimeInterval, limit: Int?) async -> HostdOutputRead {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while true {
            let output = outputLock.withLock {
                outputBuffer.read(after: sequence, limit: limit)
            }
            let running = isRunning
            if !output.chunks.isEmpty || Date() >= deadline || !running {
                if !running {
                    return HostdOutputRead(
                        chunks: output.chunks,
                        nextSequence: output.nextSequence,
                        truncated: output.truncated,
                        streamEnded: true
                    )
                }
                return output
            }
            try? await Task.sleep(nanoseconds: HostdPTYSession.outputPollNanoseconds)
        }
    }

    func readTerminalSnapshot() -> HostdOutputRead {
        terminalSnapshot.outputRead()
    }

    func writeInput(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return write(masterFD, baseAddress.advanced(by: offset), data.count - offset)
            }
            if count > 0 {
                offset += count
                continue
            }
            if count == 0 {
                throw HostdProcessRegistryError.writeFailed(code: EIO, message: errnoMessage(EIO))
            }
            let code = errno
            if code == EAGAIN || code == EWOULDBLOCK {
                try await Task.sleep(nanoseconds: 10_000_000)
                continue
            }
            throw HostdProcessRegistryError.writeFailed(code: code, message: errnoMessage(code))
        }
    }

    func resize(columns: UInt16, rows: UInt16) throws {
        guard columns > 0, rows > 0 else {
            throw HostdProcessRegistryError.resizeFailed(code: EINVAL, message: errnoMessage(EINVAL))
        }
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        guard ioctl(masterFD, TIOCSWINSZ, &size) == 0 else {
            throw HostdProcessRegistryError.resizeFailed(code: errno, message: errnoMessage())
        }
        terminalSnapshot.resize(columns: columns, rows: rows)
    }

    func sendSignal(_ signal: HostdSessionSignal) throws {
        let result = stateLock.withLock {
            if reaped { return CInt(ESRCH) }
            return sendProcessSignal(signal.value)
        }
        guard result == 0 else {
            throw HostdProcessRegistryError.signalFailed(code: result, message: errnoMessage(result))
        }
    }

    func terminate() throws {
        let result = stateLock.withLock {
            if reaped { return CInt(0) }
            let terminateResult = sendProcessSignal(SIGTERM)
            if terminateResult != 0 {
                return terminateResult
            }
            if waitForExit(timeout: 0.5) {
                return CInt(0)
            }
            let forceResult = sendProcessSignal(SIGKILL)
            if forceResult != 0 {
                return forceResult
            }
            return waitForExit(timeout: 1) ? CInt(0) : CInt(ETIMEDOUT)
        }
        closeMaster()
        guard result == 0 else {
            throw HostdProcessRegistryError.terminateFailed(code: result, message: errnoMessage(result))
        }
    }

    private func waitForExit(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var status: CInt = 0
            let result = waitpid(pid, &status, WNOHANG)
            if result == pid || (result == -1 && errno == ECHILD) {
                reaped = true
                return true
            }
            usleep(10000)
        }
        return false
    }

    private func sendProcessSignal(_ signal: CInt) -> CInt {
        let groupResult = kill(-pid, signal)
        if groupResult == 0 { return CInt(0) }
        let groupError = errno
        let processResult = kill(pid, signal)
        if processResult == 0 { return CInt(0) }
        let processError = errno
        if groupError == ESRCH || processError == ESRCH { return CInt(0) }
        return groupError
    }

    private func closeMaster() {
        let task = stateLock.withLock {
            guard !closed else { return nil as Task<Void, Never>? }
            close(masterFD)
            closed = true
            return outputPumpTask
        }
        task?.cancel()
    }

    private func startOutputPump() {
        outputPumpTask = Task.detached { [weak self] in
            await self?.pumpOutput()
        }
    }

    private func pumpOutput() async {
        while !Task.isCancelled {
            do {
                let result = try readPTYAvailable()
                if !result.data.isEmpty {
                    let sequence = outputLock.withLock {
                        outputBuffer.append(result.data)
                        return outputBuffer.nextSequence
                    }
                    terminalSnapshot.feed(result.data, endingAt: sequence)
                }
                if result.closed || !isRunning {
                    return
                }
                if result.data.isEmpty {
                    try? await Task.sleep(nanoseconds: HostdPTYSession.outputPollNanoseconds)
                }
            } catch {
                return
            }
        }
    }

    private func readPTYAvailable() throws -> HostdPTYReadResult {
        var output = Data()
        while true {
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = buffer.withUnsafeMutableBytes { rawBuffer in
                read(masterFD, rawBuffer.baseAddress, rawBuffer.count)
            }
            if count > 0 {
                output.append(contentsOf: buffer.prefix(count))
                continue
            }
            if count == 0 || errno == EIO {
                return HostdPTYReadResult(data: output, closed: true)
            }
            let code = errno
            if code == EAGAIN || code == EWOULDBLOCK {
                return HostdPTYReadResult(data: output, closed: false)
            }
            throw HostdProcessRegistryError.readFailed(code: code, message: errnoMessage(code))
        }
    }

    private static func configureNonBlocking(fd: CInt) throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0 else {
            throw HostdProcessRegistryError.configurePTYFailed(code: errno, message: errnoMessage())
        }
        guard fcntl(fd, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw HostdProcessRegistryError.configurePTYFailed(code: errno, message: errnoMessage())
        }
    }

    private static func spawn(
        command: String,
        cwd: String,
        environment: [String: String],
        masterFD: CInt,
        slaveFD: CInt,
        slavePath: String
    ) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        var actionResult = posix_spawn_file_actions_init(&actions)
        guard actionResult == 0 else {
            throw HostdProcessRegistryError.spawnFailed(code: actionResult, message: errnoMessage(actionResult))
        }
        defer { posix_spawn_file_actions_destroy(&actions) }

        actionResult = slavePath.withCString { path in
            posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, path, O_RDWR, mode_t(0))
        }
        guard actionResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: actionResult, message: errnoMessage(actionResult)) }
        actionResult = posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDOUT_FILENO)
        guard actionResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: actionResult, message: errnoMessage(actionResult)) }
        actionResult = posix_spawn_file_actions_adddup2(&actions, STDIN_FILENO, STDERR_FILENO)
        guard actionResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: actionResult, message: errnoMessage(actionResult)) }
        actionResult = posix_spawn_file_actions_addclose(&actions, masterFD)
        guard actionResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: actionResult, message: errnoMessage(actionResult)) }
        actionResult = posix_spawn_file_actions_addclose(&actions, slaveFD)
        guard actionResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: actionResult, message: errnoMessage(actionResult)) }
        actionResult = posix_spawn_file_actions_addchdir_np(&actions, cwd)
        guard actionResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: actionResult, message: errnoMessage(actionResult)) }

        var attributes: posix_spawnattr_t?
        var attrResult = posix_spawnattr_init(&attributes)
        guard attrResult == 0 else {
            throw HostdProcessRegistryError.spawnFailed(code: attrResult, message: errnoMessage(attrResult))
        }
        defer { posix_spawnattr_destroy(&attributes) }

        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        sigaddset(&defaultSignals, SIGINT)
        sigaddset(&defaultSignals, SIGTERM)
        sigaddset(&defaultSignals, SIGQUIT)
        attrResult = posix_spawnattr_setsigdefault(&attributes, &defaultSignals)
        guard attrResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: attrResult, message: errnoMessage(attrResult)) }

        var signalMask = sigset_t()
        sigemptyset(&signalMask)
        attrResult = posix_spawnattr_setsigmask(&attributes, &signalMask)
        guard attrResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: attrResult, message: errnoMessage(attrResult)) }
        attrResult = posix_spawnattr_setflags(
            &attributes,
            Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK)
        )
        guard attrResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: attrResult, message: errnoMessage(attrResult)) }

        let args = ["/bin/sh", "-lc", command]
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            env[key] = value
        }
        let envStrings = env.map { "\($0.key)=\($0.value)" }.sorted()
        var pid: pid_t = 0
        let result = withCStringArray(args) { argv in
            withCStringArray(envStrings) { envp in
                "/bin/sh".withCString { path in
                    posix_spawn(&pid, path, &actions, &attributes, argv, envp)
                }
            }
        }
        guard result == 0 else {
            throw HostdProcessRegistryError.spawnFailed(code: result, message: errnoMessage(result))
        }
        return pid
    }
}

private struct HostdPTYReadResult {
    let data: Data
    let closed: Bool
}

private extension HostdSessionSignal {
    var value: CInt {
        switch self {
        case .interrupt:
            SIGINT
        }
    }
}

private func withCStringArray<Result>(
    _ strings: [String],
    _ body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) throws -> Result
) rethrows -> Result {
    let cStrings = strings.map { strdup($0) }
    defer {
        for cString in cStrings {
            free(cString)
        }
    }
    var array = cStrings + [nil]
    return try array.withUnsafeMutableBufferPointer { buffer in
        try body(buffer.baseAddress)
    }
}

private func errnoMessage(_ code: Int32 = errno) -> String {
    String(cString: strerror(code))
}
