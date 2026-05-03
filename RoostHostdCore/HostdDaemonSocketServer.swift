import Darwin
import Dispatch
import Foundation

public final class HostdDaemonSocketServer: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.roost.hostd.daemon.socket")
    private let socketPath: String
    private let registry: HostdProcessRegistry
    private var serverFD: CInt = -1
    private var acceptSource: DispatchSourceRead?

    public init(socketPath: String = HostdDaemonSocket.defaultSocketPath, registry: HostdProcessRegistry) {
        self.socketPath = socketPath
        self.registry = registry
    }

    public func start() {
        queue.async { [weak self] in
            self?.startListening()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            self?.cleanup()
        }
    }

    public func handle(_ request: HostdAttachSocketRequest) async throws -> HostdAttachSocketResponse {
        let payload: Data
        switch request.operation {
        case .runtimeIdentity:
            payload = try HostdXPCCodec.success(HostdDaemonRuntimeIdentity())
        case .runtimeOwnership:
            payload = try HostdXPCCodec.success(HostdRuntimeOwnership.hostdOwnedProcess)
        case .createSession:
            let request = try HostdXPCCodec.decode(HostdCreateSessionRequest.self, from: request.payload)
            guard let command = request.command else {
                throw HostdProcessRegistryError.emptyCommand
            }
            _ = try await registry.launchSession(HostdLaunchSessionRequest(
                id: request.id,
                projectID: request.projectID,
                worktreeID: request.worktreeID,
                workspacePath: request.workspacePath,
                agentKind: request.agentKind,
                command: command,
                createdAt: request.createdAt,
                environment: request.environment
            ))
            payload = try HostdXPCCodec.success()
        case .markExited:
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request.payload)
            try await registry.terminateSession(id: request.id)
            payload = try HostdXPCCodec.success()
        case .listLiveSessions:
            let records = try await registry.listLiveSessions()
            payload = try HostdXPCCodec.success(records)
        case .listAllSessions:
            let records = try await registry.listAllSessions()
            payload = try HostdXPCCodec.success(records)
        case .deleteSession:
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request.payload)
            try await registry.deleteSession(id: request.id)
            payload = try HostdXPCCodec.success()
        case .pruneExited:
            try await registry.pruneExited()
            payload = try HostdXPCCodec.success()
        case .markAllRunningExited:
            payload = try HostdXPCCodec.success()
        case .attachSession:
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request.payload)
            let response = try await registry.attachSession(id: request.id)
            payload = try HostdXPCCodec.success(response)
        case .releaseSession:
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request.payload)
            try await registry.releaseSession(id: request.id)
            payload = try HostdXPCCodec.success()
        case .terminateSession:
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request.payload)
            try await registry.terminateSession(id: request.id)
            payload = try HostdXPCCodec.success()
        case .readSessionOutput:
            let request = try HostdXPCCodec.decode(HostdReadSessionOutputRequest.self, from: request.payload)
            let output = try await registry.readAvailableOutput(id: request.id, timeout: request.timeout)
            payload = try HostdXPCCodec.success(HostdReadSessionOutputResponse(data: output))
        case .readSessionOutputStream:
            let request = try HostdXPCCodec.decode(HostdReadSessionOutputStreamRequest.self, from: request.payload)
            let output = try await registry.readSessionOutputStream(
                id: request.id,
                after: request.after,
                timeout: request.timeout,
                limit: request.limit,
                mode: request.mode
            )
            payload = try HostdXPCCodec.success(HostdReadSessionOutputStreamResponse(output: output))
        case .writeSessionInput:
            let request = try HostdXPCCodec.decode(HostdWriteSessionInputRequest.self, from: request.payload)
            try await registry.writeSessionInput(id: request.id, data: request.data)
            payload = try HostdXPCCodec.success()
        case .resizeSession:
            let request = try HostdXPCCodec.decode(HostdResizeSessionRequest.self, from: request.payload)
            try await registry.resizeSession(id: request.id, columns: request.columns, rows: request.rows)
            payload = try HostdXPCCodec.success()
        case .sendSessionSignal:
            let request = try HostdXPCCodec.decode(HostdSendSessionSignalRequest.self, from: request.payload)
            try await registry.sendSessionSignal(id: request.id, signal: request.signal)
            payload = try HostdXPCCodec.success()
        }
        return HostdAttachSocketResponse(payload: payload)
    }

    private func startListening() {
        cleanup()
        guard socketPath.utf8.count <= HostdSocketIO.maxSocketPathLength else { return }
        unlink(socketPath)
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { return }
        guard (try? HostdSocketIO.setCloseOnExec(serverFD)) != nil else {
            close(serverFD)
            serverFD = -1
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { $0 }
            _ = socketPath.withCString { strncpy(bound, $0, 103) }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverFD)
            serverFD = -1
            return
        }

        chmod(socketPath, mode_t(0o600))
        guard listen(serverFD, 16) == 0 else {
            close(serverFD)
            serverFD = -1
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.serverFD >= 0 else { return }
            close(self.serverFD)
            self.serverFD = -1
            unlink(self.socketPath)
        }
        acceptSource = source
        source.resume()
    }

    private func acceptConnection() {
        let fd = accept(serverFD, nil, nil)
        guard fd >= 0 else { return }
        guard (try? HostdSocketIO.setCloseOnExec(fd)) != nil else {
            close(fd)
            return
        }
        Task {
            await handleClient(fd)
        }
    }

    private func handleClient(_ fd: CInt) async {
        do {
            let requestData = try HostdSocketIO.readAll(from: fd)
            let request = try JSONDecoder().decode(HostdAttachSocketRequest.self, from: requestData)
            let response = try await handle(request)
            let responseData = try JSONEncoder().encode(response)
            try HostdSocketIO.writeAll(responseData, to: fd)
        } catch {
            let response = HostdAttachSocketResponse(payload: HostdXPCCodec.failure(error.localizedDescription))
            if let data = try? JSONEncoder().encode(response) {
                try? HostdSocketIO.writeAll(data, to: fd)
            }
        }
        close(fd)
    }

    private func cleanup() {
        acceptSource?.cancel()
        acceptSource = nil
    }
}
