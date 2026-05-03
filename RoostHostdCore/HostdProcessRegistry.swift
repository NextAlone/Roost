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
    case openPTYFailed(code: Int32, message: String)
    case configurePTYFailed(code: Int32, message: String)
    case spawnFailed(code: Int32, message: String)
    case readFailed(code: Int32, message: String)
    case terminateFailed(code: Int32, message: String)

    public var errorDescription: String? {
        switch self {
        case .emptyCommand:
            "Hostd cannot launch an empty command"
        case let .sessionNotFound(id):
            "Hostd session \(id.uuidString) is not running"
        case let .openPTYFailed(code, message):
            "Hostd failed to open PTY: \(message) (\(code))"
        case let .configurePTYFailed(code, message):
            "Hostd failed to configure PTY: \(message) (\(code))"
        case let .spawnFailed(code, message):
            "Hostd failed to spawn session process: \(message) (\(code))"
        case let .readFailed(code, message):
            "Hostd failed to read session output: \(message) (\(code))"
        case let .terminateFailed(code, message):
            "Hostd failed to terminate session process: \(message) (\(code))"
        }
    }
}

public actor HostdProcessRegistry {
    private let store: SessionStore
    private var sessions: [UUID: HostdPTYSession] = [:]

    init(store: SessionStore) {
        self.store = store
    }

    public init(databaseURL: URL = HostdStorage.defaultDatabaseURL()) async throws {
        self.store = try await SessionStore(url: databaseURL)
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
        return HostdAttachSessionResponse(record: session.record, ownership: .hostdOwnedProcess)
    }

    public func releaseSession(id: UUID) async throws {
        guard sessions[id] != nil else { throw HostdProcessRegistryError.sessionNotFound(id) }
    }

    public func terminateSession(id: UUID) async throws {
        guard let session = sessions.removeValue(forKey: id) else {
            throw HostdProcessRegistryError.sessionNotFound(id)
        }
        try session.terminate()
        try await store.update(id: id, lastState: .exited)
    }

    public func listLiveSessions() async throws -> [SessionRecord] {
        try await store.listLive()
    }

    public func listAllSessions() async throws -> [SessionRecord] {
        try await store.list()
    }

    public func deleteSession(id: UUID) async throws {
        if let session = sessions.removeValue(forKey: id) {
            try session.terminate()
        }
        try await store.delete(id: id)
    }

    public func pruneExited() async throws {
        try await store.pruneExited()
    }

    public func readAvailableOutput(id: UUID, timeout: TimeInterval = 0) async throws -> Data {
        guard let session = sessions[id] else { throw HostdProcessRegistryError.sessionNotFound(id) }
        return try await session.readAvailableOutput(timeout: timeout)
    }

    private func markExitedIfKnown(id: UUID) async throws {
        sessions.removeValue(forKey: id)
        try await store.update(id: id, lastState: .exited)
    }
}

private final class HostdPTYSession: @unchecked Sendable {
    let record: SessionRecord
    private let pid: pid_t
    private let masterFD: CInt
    private let lock = NSLock()
    private var closed = false
    private var reaped = false

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

    static func launch(record: SessionRecord, command: String, environment: [String: String]) throws -> HostdPTYSession {
        var masterFD: CInt = -1
        var slaveFD: CInt = -1
        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw HostdProcessRegistryError.openPTYFailed(code: errno, message: errnoMessage())
        }
        do {
            try configureNonBlocking(fd: masterFD)
            let pid = try spawn(command: command, cwd: record.workspacePath, environment: environment, masterFD: masterFD, slaveFD: slaveFD)
            close(slaveFD)
            return HostdPTYSession(record: record, pid: pid, masterFD: masterFD)
        } catch {
            close(masterFD)
            close(slaveFD)
            throw error
        }
    }

    func readAvailableOutput(timeout: TimeInterval) async throws -> Data {
        let deadline = Date().addingTimeInterval(max(0, timeout))
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
                return output
            }
            let code = errno
            if code == EAGAIN || code == EWOULDBLOCK {
                if !output.isEmpty || Date() >= deadline {
                    return output
                }
                try await Task.sleep(nanoseconds: 10_000_000)
                continue
            }
            throw HostdProcessRegistryError.readFailed(code: code, message: errnoMessage(code))
        }
    }

    func terminate() throws {
        let result = lock.withLock {
            if reaped { return CInt(0) }
            let killResult = kill(pid, SIGTERM)
            if killResult != 0 && errno != ESRCH {
                return errno
            }
            if waitForExit(timeout: 0.5) {
                return CInt(0)
            }
            let forceResult = kill(pid, SIGKILL)
            if forceResult != 0 && errno != ESRCH {
                return errno
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

    private func closeMaster() {
        lock.withLock {
            guard !closed else { return }
            close(masterFD)
            closed = true
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
        slaveFD: CInt
    ) throws -> pid_t {
        var actions: posix_spawn_file_actions_t?
        var actionResult = posix_spawn_file_actions_init(&actions)
        guard actionResult == 0 else {
            throw HostdProcessRegistryError.spawnFailed(code: actionResult, message: errnoMessage(actionResult))
        }
        defer { posix_spawn_file_actions_destroy(&actions) }

        actionResult = posix_spawn_file_actions_adddup2(&actions, slaveFD, STDIN_FILENO)
        guard actionResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: actionResult, message: errnoMessage(actionResult)) }
        actionResult = posix_spawn_file_actions_adddup2(&actions, slaveFD, STDOUT_FILENO)
        guard actionResult == 0
        else { throw HostdProcessRegistryError.spawnFailed(code: actionResult, message: errnoMessage(actionResult)) }
        actionResult = posix_spawn_file_actions_adddup2(&actions, slaveFD, STDERR_FILENO)
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
                    posix_spawn(&pid, path, &actions, nil, argv, envp)
                }
            }
        }
        guard result == 0 else {
            throw HostdProcessRegistryError.spawnFailed(code: result, message: errnoMessage(result))
        }
        return pid
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
