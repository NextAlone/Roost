import Darwin
import Foundation
import MuxyShared

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
        }
    }
}

public actor HostdProcessRegistry {
    private let store: SessionStore
    private let keepalive: any HostdProcessKeepalive
    private var sessions: [UUID: HostdPTYSession] = [:]

    init(store: SessionStore, keepalive: any HostdProcessKeepalive = NoopHostdProcessKeepalive()) {
        self.store = store
        self.keepalive = keepalive
    }

    public init(
        databaseURL: URL = HostdStorage.defaultDatabaseURL(),
        keepalive: any HostdProcessKeepalive = NoopHostdProcessKeepalive()
    ) async throws {
        self.store = try await SessionStore(url: databaseURL)
        self.keepalive = keepalive
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
        let session = try HostdPTYSession.launch(record: record, command: command, environment: request.environment)
        do {
            try await store.record(record)
            sessions[request.id] = session
            keepalive.retainSession()
            startExitWatcher(id: request.id, session: session)
            return HostdAttachSessionResponse(record: record, ownership: .hostdOwnedProcess)
        } catch {
            try? session.terminate()
            throw error
        }
    }

    public func attachSession(id: UUID) async throws -> HostdAttachSessionResponse {
        guard let session = sessions[id], session.isRunning else {
            try await markExitedIfKnown(id: id)
            throw HostdProcessRegistryError.sessionNotFound(id)
        }
        let count = session.attach()
        return HostdAttachSessionResponse(
            record: session.record,
            ownership: .hostdOwnedProcess,
            attachedClientCount: count
        )
    }

    public func releaseSession(id: UUID) async throws {
        guard let session = sessions[id] else { throw HostdProcessRegistryError.sessionNotFound(id) }
        try session.release()
    }

    public func terminateSession(id: UUID) async throws {
        guard let session = sessions.removeValue(forKey: id) else {
            throw HostdProcessRegistryError.sessionNotFound(id)
        }
        keepalive.releaseSession()
        try session.terminate()
        try await store.update(id: id, lastState: .exited)
    }

    public func listLiveSessions() async throws -> [SessionRecord] {
        let persistedLive = try await store.listLive()
        let liveSessions = sessions.filter { $0.value.isRunning }
        let deadIDs = Set(sessions.keys).subtracting(liveSessions.keys)
        for id in deadIDs {
            sessions.removeValue(forKey: id)
            keepalive.releaseSession()
            try await store.update(id: id, lastState: .exited)
        }

        let liveRecords = liveSessions.values
            .map(\.record)
            .sorted { $0.createdAt > $1.createdAt }
        let liveIDs = Set(liveRecords.map(\.id))
        for record in persistedLive where !liveIDs.contains(record.id) {
            try await store.update(id: record.id, lastState: .exited)
        }
        return liveRecords
    }

    public func listAllSessions() async throws -> [SessionRecord] {
        try await store.list()
    }

    public func deleteSession(id: UUID) async throws {
        if let session = sessions.removeValue(forKey: id) {
            keepalive.releaseSession()
            try session.terminate()
        }
        try await store.delete(id: id)
    }

    public func pruneExited() async throws {
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
        limit: Int? = nil
    ) async throws -> HostdOutputRead {
        guard let session = sessions[id] else { throw HostdProcessRegistryError.sessionNotFound(id) }
        return await session.readOutput(after: sequence, timeout: timeout, limit: limit)
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

    private func markExitedIfKnown(id: UUID) async throws {
        if sessions.removeValue(forKey: id) != nil {
            keepalive.releaseSession()
        }
        try await store.update(id: id, lastState: .exited)
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
        guard sessions.removeValue(forKey: id) != nil else { return }
        keepalive.releaseSession()
        try? await store.update(id: id, lastState: .exited)
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
    private let lock = NSLock()
    private var closed = false
    private var reaped = false
    private var attachedClientCount = 0
    private var outputBuffer = HostdOutputRingBuffer(limit: HostdPTYSession.outputBufferLimit)
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
        lock.withLock {
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
        lock.withLock {
            attachedClientCount += 1
            return attachedClientCount
        }
    }

    func release() throws {
        let result = lock.withLock {
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
        let sequence = lock.withLock { compatibilityReadSequence }
        let output = await readOutput(after: sequence, timeout: timeout, limit: nil)
        lock.withLock {
            compatibilityReadSequence = output.nextSequence
        }
        return output.chunks.reduce(into: Data()) { data, chunk in
            data.append(chunk.data)
        }
    }

    func readOutput(after sequence: UInt64?, timeout: TimeInterval, limit: Int?) async -> HostdOutputRead {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        while true {
            let output = lock.withLock {
                outputBuffer.read(after: sequence, limit: limit)
            }
            if !output.chunks.isEmpty || Date() >= deadline || !isRunning {
                return output
            }
            try? await Task.sleep(nanoseconds: HostdPTYSession.outputPollNanoseconds)
        }
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
    }

    func sendSignal(_ signal: HostdSessionSignal) throws {
        let result = lock.withLock {
            if reaped { return CInt(ESRCH) }
            return sendProcessSignal(signal.value)
        }
        guard result == 0 else {
            throw HostdProcessRegistryError.signalFailed(code: result, message: errnoMessage(result))
        }
    }

    func terminate() throws {
        let result = lock.withLock {
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
        let task = lock.withLock {
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
                    lock.withLock {
                        outputBuffer.append(result.data)
                    }
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
