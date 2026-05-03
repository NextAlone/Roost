import Darwin
import Foundation
import os
import RoostHostdCore

private let hostdAttachSocketLogger = Logger(subsystem: "app.muxy", category: "HostdAttachSocketServer")

final class HostdAttachSocketServer: @unchecked Sendable {
    static let shared = HostdAttachSocketServer()

    private static let maxMessageSize = 16 * 1024 * 1024
    private static let maxSocketPathLength = 103
    private let queue = DispatchQueue(label: "app.muxy.hostdAttachSocket")
    private let socketPath: String
    private let lock = NSLock()
    private var client: (any RoostHostdClient)?
    private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    static var defaultSocketPath: String {
        "/tmp/roost-hostd-attach-\(getuid())-\(getpid()).sock"
    }

    init(socketPath: String = HostdAttachSocketServer.defaultSocketPath, client: (any RoostHostdClient)? = nil) {
        self.socketPath = socketPath
        self.client = client
    }

    func updateClient(_ client: (any RoostHostdClient)?) {
        lock.withLock {
            self.client = client
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.startListening()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.cleanup()
        }
    }

    func handle(_ request: HostdAttachSocketRequest) async throws -> HostdAttachSocketResponse {
        let payload: Data
        switch request.operation {
        case .runtimeIdentity:
            payload = try HostdXPCCodec.success(HostdDaemonRuntimeIdentity())
        case .runtimeOwnership:
            let ownership = try await currentClient().runtimeOwnership()
            payload = try HostdXPCCodec.success(ownership)
        case .createSession:
            let request = try HostdXPCCodec.decode(HostdCreateSessionRequest.self, from: request.payload)
            try await currentClient().createSession(request)
            payload = try HostdXPCCodec.success()
        case .markExited:
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request.payload)
            try await currentClient().markExited(sessionID: request.id)
            payload = try HostdXPCCodec.success()
        case .listLiveSessions:
            let records = try await currentClient().listLiveSessions()
            payload = try HostdXPCCodec.success(records)
        case .listAllSessions:
            let records = try await currentClient().listAllSessions()
            payload = try HostdXPCCodec.success(records)
        case .deleteSession:
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request.payload)
            try await currentClient().deleteSession(id: request.id)
            payload = try HostdXPCCodec.success()
        case .pruneExited:
            try await currentClient().pruneExited()
            payload = try HostdXPCCodec.success()
        case .markAllRunningExited:
            try await currentClient().markAllRunningExited()
            payload = try HostdXPCCodec.success()
        case .attachSession:
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request.payload)
            let response = try await currentClient().attachSession(id: request.id)
            payload = try HostdXPCCodec.success(response)
        case .releaseSession:
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request.payload)
            try await currentClient().releaseSession(id: request.id)
            payload = try HostdXPCCodec.success()
        case .terminateSession:
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request.payload)
            try await currentClient().terminateSession(id: request.id)
            payload = try HostdXPCCodec.success()
        case .readSessionOutput:
            let request = try HostdXPCCodec.decode(HostdReadSessionOutputRequest.self, from: request.payload)
            let output = try await currentClient().readSessionOutput(id: request.id, timeout: request.timeout)
            payload = try HostdXPCCodec.success(HostdReadSessionOutputResponse(data: output))
        case .readSessionOutputStream:
            let request = try HostdXPCCodec.decode(HostdReadSessionOutputStreamRequest.self, from: request.payload)
            let output = try await currentClient().readSessionOutputStream(
                id: request.id,
                after: request.after,
                timeout: request.timeout
            )
            payload = try HostdXPCCodec.success(HostdReadSessionOutputStreamResponse(output: output))
        case .writeSessionInput:
            let request = try HostdXPCCodec.decode(HostdWriteSessionInputRequest.self, from: request.payload)
            try await currentClient().writeSessionInput(id: request.id, data: request.data)
            payload = try HostdXPCCodec.success()
        case .resizeSession:
            let request = try HostdXPCCodec.decode(HostdResizeSessionRequest.self, from: request.payload)
            try await currentClient().resizeSession(id: request.id, columns: request.columns, rows: request.rows)
            payload = try HostdXPCCodec.success()
        case .sendSessionSignal:
            let request = try HostdXPCCodec.decode(HostdSendSessionSignalRequest.self, from: request.payload)
            try await currentClient().sendSessionSignal(id: request.id, signal: request.signal)
            payload = try HostdXPCCodec.success()
        }
        return HostdAttachSocketResponse(payload: payload)
    }

    private func currentClient() throws -> any RoostHostdClient {
        guard let client = lock.withLock({ client }) else {
            throw HostdAttachSocketServerError.clientUnavailable
        }
        return client
    }

    private func startListening() {
        cleanup()
        let path = socketPath
        guard path.utf8.count <= Self.maxSocketPathLength else {
            hostdAttachSocketLogger.error("Hostd attach socket path is too long")
            return
        }
        unlink(path)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            hostdAttachSocketLogger.error("Failed to create socket: \(String(cString: strerror(errno)))")
            return
        }
        guard (try? HostdSocketIO.setCloseOnExec(serverFD)) != nil else {
            hostdAttachSocketLogger.error("Failed to configure hostd attach socket")
            close(serverFD)
            serverFD = -1
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let bound = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { $0 }
            _ = path.withCString { strncpy(bound, $0, 103) }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFD, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            hostdAttachSocketLogger.error("Failed to bind socket: \(String(cString: strerror(errno)))")
            close(serverFD)
            serverFD = -1
            return
        }

        chmod(path, mode_t(FilePermissions.privateFile))

        guard listen(serverFD, 16) == 0 else {
            hostdAttachSocketLogger.error("Failed to listen on socket: \(String(cString: strerror(errno)))")
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
            unlink(path)
        }
        acceptSource = source
        source.resume()
        hostdAttachSocketLogger.info("Hostd attach socket listening at \(path)")
    }

    private func acceptConnection() {
        let clientFD = accept(serverFD, nil, nil)
        guard clientFD >= 0 else { return }
        guard (try? HostdSocketIO.setCloseOnExec(clientFD)) != nil else {
            close(clientFD)
            return
        }
        queue.async { [weak self] in
            self?.handleClient(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        Task {
            do {
                let requestData = try Self.readMessage(from: fd)
                let request = try JSONDecoder().decode(HostdAttachSocketRequest.self, from: requestData)
                let response = try await handle(request)
                let responseData = try JSONEncoder().encode(response)
                try Self.writeAll(responseData, to: fd)
            } catch {
                let response = HostdAttachSocketResponse(payload: HostdXPCCodec.failure(error.localizedDescription))
                if let data = try? JSONEncoder().encode(response) {
                    try? Self.writeAll(data, to: fd)
                }
            }
            close(fd)
        }
    }

    private static func readMessage(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = read(fd, &buffer, buffer.count)
            if bytesRead > 0 {
                data.append(contentsOf: buffer[0 ..< bytesRead])
                if data.count > maxMessageSize {
                    throw HostdAttachSocketServerError.messageTooLarge
                }
                continue
            }
            if bytesRead == 0 { break }
            if errno == EINTR { continue }
            throw HostdAttachSocketServerError.readFailed(String(cString: strerror(errno)))
        }
        return data
    }

    private static func writeAll(_ data: Data, to fd: Int32) throws {
        guard !data.isEmpty else { return }
        var offset = 0
        while offset < data.count {
            let count = data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return 0 }
                return write(fd, baseAddress.advanced(by: offset), data.count - offset)
            }
            if count > 0 {
                offset += count
                continue
            }
            if count == -1 && errno == EINTR {
                continue
            }
            throw HostdAttachSocketServerError.writeFailed(String(cString: strerror(errno)))
        }
    }

    private func cleanup() {
        acceptSource?.cancel()
        acceptSource = nil
    }
}

private enum HostdAttachSocketServerError: Error, LocalizedError {
    case clientUnavailable
    case messageTooLarge
    case readFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .clientUnavailable:
            "Roost hostd client is unavailable"
        case .messageTooLarge:
            "Hostd attach socket message is too large"
        case let .readFailed(message):
            "Hostd attach socket read failed: \(message)"
        case let .writeFailed(message):
            "Hostd attach socket write failed: \(message)"
        }
    }
}
