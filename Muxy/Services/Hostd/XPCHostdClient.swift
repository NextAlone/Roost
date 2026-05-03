import Foundation
import MuxyShared
import RoostHostdCore

protocol HostdXPCTransport: Sendable {
    func runtimeOwnership() async throws -> Data
    func createSession(_ request: Data) async throws -> Data
    func markExited(_ request: Data) async throws -> Data
    func listLiveSessions() async throws -> Data
    func listAllSessions() async throws -> Data
    func deleteSession(_ request: Data) async throws -> Data
    func pruneExited() async throws -> Data
    func markAllRunningExited() async throws -> Data
    func attachSession(_ request: Data) async throws -> Data
    func releaseSession(_ request: Data) async throws -> Data
    func terminateSession(_ request: Data) async throws -> Data
    func readSessionOutput(_ request: Data) async throws -> Data
    func readSessionOutputStream(_ request: Data) async throws -> Data
    func writeSessionInput(_ request: Data) async throws -> Data
    func resizeSession(_ request: Data) async throws -> Data
    func sendSessionSignal(_ request: Data) async throws -> Data
}

enum XPCHostdClientError: Error, LocalizedError {
    case proxyUnavailable

    var errorDescription: String? {
        switch self {
        case .proxyUnavailable:
            "Roost hostd XPC proxy is unavailable"
        }
    }
}

final class NSXPCHostdTransport: HostdXPCTransport, @unchecked Sendable {
    private let serviceName: String
    private let lock = NSLock()
    private var connection: NSXPCConnection?

    init(serviceName: String = "app.roost.mac.hostd") {
        self.serviceName = serviceName
    }

    deinit {
        lock.withLock {
            connection?.invalidate()
        }
    }

    func runtimeOwnership() async throws -> Data {
        try await call { proxy, reply in
            proxy.runtimeOwnership(reply: reply)
        }
    }

    func createSession(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.createSession(request, reply: reply)
        }
    }

    func markExited(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.markExited(request, reply: reply)
        }
    }

    func listLiveSessions() async throws -> Data {
        try await call { proxy, reply in
            proxy.listLiveSessions(reply: reply)
        }
    }

    func listAllSessions() async throws -> Data {
        try await call { proxy, reply in
            proxy.listAllSessions(reply: reply)
        }
    }

    func deleteSession(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.deleteSession(request, reply: reply)
        }
    }

    func pruneExited() async throws -> Data {
        try await call { proxy, reply in
            proxy.pruneExited(reply: reply)
        }
    }

    func markAllRunningExited() async throws -> Data {
        try await call { proxy, reply in
            proxy.markAllRunningExited(reply: reply)
        }
    }

    func attachSession(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.attachSession(request, reply: reply)
        }
    }

    func releaseSession(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.releaseSession(request, reply: reply)
        }
    }

    func terminateSession(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.terminateSession(request, reply: reply)
        }
    }

    func readSessionOutput(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.readSessionOutput(request, reply: reply)
        }
    }

    func readSessionOutputStream(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.readSessionOutputStream(request, reply: reply)
        }
    }

    func writeSessionInput(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.writeSessionInput(request, reply: reply)
        }
    }

    func resizeSession(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.resizeSession(request, reply: reply)
        }
    }

    func sendSessionSignal(_ request: Data) async throws -> Data {
        try await call { proxy, reply in
            proxy.sendSessionSignal(request, reply: reply)
        }
    }

    private func call(
        _ body: @escaping @Sendable (RoostHostdXPCProtocol, @escaping @Sendable (Data) -> Void) -> Void
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            do {
                let proxy = try remoteProxy { error in
                    continuation.resume(throwing: error)
                }
                body(proxy) { data in
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
        guard let proxy else { throw XPCHostdClientError.proxyUnavailable }
        return proxy
    }
}

struct XPCHostdClient: RoostHostdClient {
    private let transport: any HostdXPCTransport
    private let requestTimeout: TimeInterval

    init(transport: any HostdXPCTransport = NSXPCHostdTransport(), requestTimeout: TimeInterval = 8) {
        self.transport = transport
        self.requestTimeout = requestTimeout
    }

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        let response = try await withRequestTimeout("runtime ownership") {
            try await transport.runtimeOwnership()
        }
        return try HostdXPCCodec.decodeReply(HostdRuntimeOwnership.self, from: response)
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {
        let encoded = try HostdXPCCodec.encode(request)
        let response = try await withRequestTimeout("create session") {
            try await transport.createSession(encoded)
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func attachSession(id: UUID) async throws -> HostdAttachSessionResponse {
        let request = try HostdXPCCodec.encode(HostdSessionIDRequest(id: id))
        let response = try await withRequestTimeout("attach session") {
            try await transport.attachSession(request)
        }
        return try HostdXPCCodec.decodeReply(HostdAttachSessionResponse.self, from: response)
    }

    func releaseSession(id: UUID) async throws {
        let request = try HostdXPCCodec.encode(HostdSessionIDRequest(id: id))
        let response = try await withRequestTimeout("release session") {
            try await transport.releaseSession(request)
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func terminateSession(id: UUID) async throws {
        let request = try HostdXPCCodec.encode(HostdSessionIDRequest(id: id))
        let response = try await withRequestTimeout("terminate session") {
            try await transport.terminateSession(request)
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func readSessionOutput(id: UUID, timeout: TimeInterval = 0) async throws -> Data {
        let request = try HostdXPCCodec.encode(HostdReadSessionOutputRequest(
            id: id,
            timeout: timeout
        ))
        let response = try await withRequestTimeout("read session output", seconds: max(requestTimeout, timeout + 1)) {
            try await transport.readSessionOutput(request)
        }
        let output = try HostdXPCCodec.decodeReply(HostdReadSessionOutputResponse.self, from: response)
        return output.data
    }

    func readSessionOutputStream(
        id: UUID,
        after sequence: UInt64?,
        timeout: TimeInterval = 0,
        limit: Int? = nil
    ) async throws -> HostdOutputRead {
        let request = try HostdXPCCodec.encode(HostdReadSessionOutputStreamRequest(
            id: id,
            after: sequence,
            timeout: timeout,
            limit: limit
        ))
        let response = try await withRequestTimeout("read session output stream", seconds: max(requestTimeout, timeout + 1)) {
            try await transport.readSessionOutputStream(request)
        }
        let output = try HostdXPCCodec.decodeReply(HostdReadSessionOutputStreamResponse.self, from: response)
        return output.output
    }

    func writeSessionInput(id: UUID, data: Data) async throws {
        let request = try HostdXPCCodec.encode(HostdWriteSessionInputRequest(
            id: id,
            data: data
        ))
        let response = try await withRequestTimeout("write session input") {
            try await transport.writeSessionInput(request)
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func resizeSession(id: UUID, columns: UInt16, rows: UInt16) async throws {
        let request = try HostdXPCCodec.encode(HostdResizeSessionRequest(
            id: id,
            columns: columns,
            rows: rows
        ))
        let response = try await withRequestTimeout("resize session") {
            try await transport.resizeSession(request)
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func sendSessionSignal(id: UUID, signal: HostdSessionSignal) async throws {
        let request = try HostdXPCCodec.encode(HostdSendSessionSignalRequest(
            id: id,
            signal: signal
        ))
        let response = try await withRequestTimeout("send session signal") {
            try await transport.sendSessionSignal(request)
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func markExited(sessionID: UUID) async throws {
        let request = try HostdXPCCodec.encode(HostdSessionIDRequest(id: sessionID))
        let response = try await withRequestTimeout("mark session exited") {
            try await transport.markExited(request)
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func listLiveSessions() async throws -> [SessionRecord] {
        let response = try await withRequestTimeout("list live sessions") {
            try await transport.listLiveSessions()
        }
        return try HostdXPCCodec.decodeReply([SessionRecord].self, from: response)
    }

    func listAllSessions() async throws -> [SessionRecord] {
        let response = try await withRequestTimeout("list sessions") {
            try await transport.listAllSessions()
        }
        return try HostdXPCCodec.decodeReply([SessionRecord].self, from: response)
    }

    func deleteSession(id: UUID) async throws {
        let request = try HostdXPCCodec.encode(HostdSessionIDRequest(id: id))
        let response = try await withRequestTimeout("delete session") {
            try await transport.deleteSession(request)
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func pruneExited() async throws {
        let response = try await withRequestTimeout("prune exited sessions") {
            try await transport.pruneExited()
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func markAllRunningExited() async throws {
        let response = try await withRequestTimeout("mark running sessions exited") {
            try await transport.markAllRunningExited()
        }
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    private func withRequestTimeout<T: Sendable>(
        _ operation: String,
        seconds: TimeInterval? = nil,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await HostdAsyncTimeout.run(
            seconds: seconds ?? requestTimeout,
            operation: operation,
            work
        )
    }
}
