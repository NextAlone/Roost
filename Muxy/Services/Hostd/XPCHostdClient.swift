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

    init(transport: any HostdXPCTransport = NSXPCHostdTransport()) {
        self.transport = transport
    }

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        let response = try await transport.runtimeOwnership()
        return try HostdXPCCodec.decodeReply(HostdRuntimeOwnership.self, from: response)
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {
        let response = try await transport.createSession(HostdXPCCodec.encode(request))
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func attachSession(id: UUID) async throws -> HostdAttachSessionResponse {
        let response = try await transport.attachSession(HostdXPCCodec.encode(HostdSessionIDRequest(id: id)))
        return try HostdXPCCodec.decodeReply(HostdAttachSessionResponse.self, from: response)
    }

    func releaseSession(id: UUID) async throws {
        let response = try await transport.releaseSession(HostdXPCCodec.encode(HostdSessionIDRequest(id: id)))
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func terminateSession(id: UUID) async throws {
        let response = try await transport.terminateSession(HostdXPCCodec.encode(HostdSessionIDRequest(id: id)))
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func markExited(sessionID: UUID) async throws {
        let response = try await transport.markExited(HostdXPCCodec.encode(HostdSessionIDRequest(id: sessionID)))
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func listLiveSessions() async throws -> [SessionRecord] {
        let response = try await transport.listLiveSessions()
        return try HostdXPCCodec.decodeReply([SessionRecord].self, from: response)
    }

    func listAllSessions() async throws -> [SessionRecord] {
        let response = try await transport.listAllSessions()
        return try HostdXPCCodec.decodeReply([SessionRecord].self, from: response)
    }

    func deleteSession(id: UUID) async throws {
        let response = try await transport.deleteSession(HostdXPCCodec.encode(HostdSessionIDRequest(id: id)))
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func pruneExited() async throws {
        let response = try await transport.pruneExited()
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }

    func markAllRunningExited() async throws {
        let response = try await transport.markAllRunningExited()
        try HostdXPCCodec.decodeEmptyReply(from: response)
    }
}
