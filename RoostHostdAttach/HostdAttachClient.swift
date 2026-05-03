import Foundation
import RoostHostdCore

final class HostdAttachClient: @unchecked Sendable {
    private let serviceName: String
    private let socketPath: String?
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private static let maxSocketPathLength = 103

    init(serviceName: String = "app.roost.mac.hostd", socketPath: String? = nil) {
        self.serviceName = serviceName
        self.socketPath = socketPath
    }

    deinit {
        lock.withLock {
            connection?.invalidate()
        }
    }

    func attachSession(id: UUID) async throws -> HostdAttachSessionResponse {
        let request = try HostdXPCCodec.encode(HostdSessionIDRequest(id: id))
        let response = try await call(operation: .attachSession, payload: request) { proxy, reply in
            proxy.attachSession(request, reply: reply)
        }
        return try HostdXPCCodec.decodeReply(HostdAttachSessionResponse.self, from: response)
    }

    func releaseSession(id: UUID) async throws {
        let request = try HostdXPCCodec.encode(HostdSessionIDRequest(id: id))
        let response = try await call(operation: .releaseSession, payload: request) { proxy, reply in
            proxy.releaseSession(request, reply: reply)
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func readSessionOutputStream(
        id: UUID,
        after sequence: UInt64?,
        timeout: TimeInterval,
        limit: Int? = nil,
        mode: HostdOutputStreamReadMode = .raw
    ) async throws -> HostdOutputRead {
        let request = try HostdXPCCodec.encode(HostdReadSessionOutputStreamRequest(
            id: id,
            after: sequence,
            timeout: timeout,
            limit: limit,
            mode: mode
        ))
        let response = try await call(operation: .readSessionOutputStream, payload: request) { proxy, reply in
            proxy.readSessionOutputStream(
                request,
                reply: reply
            )
        }
        return try HostdXPCCodec.decodeReply(HostdReadSessionOutputStreamResponse.self, from: response).output
    }

    func writeSessionInput(id: UUID, data: Data) async throws {
        let request = try HostdXPCCodec.encode(HostdWriteSessionInputRequest(id: id, data: data))
        let response = try await call(operation: .writeSessionInput, payload: request) { proxy, reply in
            proxy.writeSessionInput(
                request,
                reply: reply
            )
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func resizeSession(id: UUID, columns: UInt16, rows: UInt16) async throws {
        let request = try HostdXPCCodec.encode(HostdResizeSessionRequest(id: id, columns: columns, rows: rows))
        let response = try await call(operation: .resizeSession, payload: request) { proxy, reply in
            proxy.resizeSession(
                request,
                reply: reply
            )
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    private func call(
        operation: HostdAttachSocketOperation,
        payload: Data,
        _ body: @escaping @Sendable (RoostHostdXPCProtocol, @escaping @Sendable (Data) -> Void) throws -> Void
    ) async throws -> Data {
        if let socketPath {
            return try await callSocket(operation: operation, payload: payload, socketPath: socketPath)
        }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            do {
                let proxy = try remoteProxy { error in
                    continuation.resume(throwing: error)
                }
                try body(proxy) { data in
                    continuation.resume(returning: data)
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func remoteProxy(errorHandler: @escaping @Sendable (Error) -> Void) throws -> RoostHostdXPCProtocol {
        let connection = lock.withLock {
            if let existing = self.connection {
                return existing
            }
            let connection = NSXPCConnection(serviceName: serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: RoostHostdXPCProtocol.self)
            connection.resume()
            self.connection = connection
            return connection
        }
        let proxy = connection.remoteObjectProxyWithErrorHandler(errorHandler) as? RoostHostdXPCProtocol
        guard let proxy else { throw HostdAttachError.proxyUnavailable }
        return proxy
    }

    private func callSocket(
        operation: HostdAttachSocketOperation,
        payload: Data,
        socketPath: String
    ) async throws -> Data {
        guard socketPath.utf8.count <= Self.maxSocketPathLength else {
            throw HostdAttachError.socketFailed("socket path is too long")
        }
        return try await Task.detached {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw HostdAttachError.socketFailed(errnoMessage()) }
            defer { close(fd) }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let bound = ptr.withMemoryRebound(to: CChar.self, capacity: 104) { $0 }
                _ = socketPath.withCString { strncpy(bound, $0, 103) }
            }

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connectResult == 0 else {
                throw HostdAttachError.socketFailed(errnoMessage())
            }

            let request = HostdAttachSocketRequest(operation: operation, payload: payload)
            let requestData = try JSONEncoder().encode(request)
            try HostdAttachTerminal.writeAll(requestData, to: fd)
            shutdown(fd, SHUT_WR)

            let responseData = try Self.readAll(from: fd)
            let response = try JSONDecoder().decode(HostdAttachSocketResponse.self, from: responseData)
            return response.payload
        }.value
    }

    private static func readAll(from fd: CInt) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer[0 ..< count])
                continue
            }
            if count == 0 { return data }
            if errno == EINTR { continue }
            throw HostdAttachError.socketFailed(errnoMessage())
        }
    }
}
