import Darwin
import Foundation
import RoostHostdCore

final class HostdSocketTransport: HostdXPCTransport, @unchecked Sendable {
    private let socketPath: String

    init(socketPath: String = HostdDaemonSocket.defaultSocketPath) {
        self.socketPath = socketPath
    }

    func runtimeIdentity() async throws -> HostdDaemonRuntimeIdentity {
        let data = try await call(.runtimeIdentity)
        return try HostdXPCCodec.decodeReply(HostdDaemonRuntimeIdentity.self, from: data)
    }

    func runtimeOwnership() async throws -> Data {
        try await call(.runtimeOwnership)
    }

    func createSession(_ request: Data) async throws -> Data {
        try await call(.createSession, payload: request)
    }

    func markExited(_ request: Data) async throws -> Data {
        try await call(.markExited, payload: request)
    }

    func listLiveSessions() async throws -> Data {
        try await call(.listLiveSessions)
    }

    func listAllSessions() async throws -> Data {
        try await call(.listAllSessions)
    }

    func deleteSession(_ request: Data) async throws -> Data {
        try await call(.deleteSession, payload: request)
    }

    func pruneExited() async throws -> Data {
        try await call(.pruneExited)
    }

    func markAllRunningExited() async throws -> Data {
        try await call(.markAllRunningExited)
    }

    func attachSession(_ request: Data) async throws -> Data {
        try await call(.attachSession, payload: request)
    }

    func releaseSession(_ request: Data) async throws -> Data {
        try await call(.releaseSession, payload: request)
    }

    func terminateSession(_ request: Data) async throws -> Data {
        try await call(.terminateSession, payload: request)
    }

    func readSessionOutput(_ request: Data) async throws -> Data {
        try await call(.readSessionOutput, payload: request)
    }

    func readSessionOutputStream(_ request: Data) async throws -> Data {
        try await call(.readSessionOutputStream, payload: request)
    }

    func writeSessionInput(_ request: Data) async throws -> Data {
        try await call(.writeSessionInput, payload: request)
    }

    func resizeSession(_ request: Data) async throws -> Data {
        try await call(.resizeSession, payload: request)
    }

    func sendSessionSignal(_ request: Data) async throws -> Data {
        try await call(.sendSessionSignal, payload: request)
    }

    private func call(_ operation: HostdAttachSocketOperation, payload: Data = Data()) async throws -> Data {
        try await Task.detached { [socketPath] in
            let fd = try HostdSocketIO.connect(path: socketPath)
            defer {
                close(fd)
            }
            let request = HostdAttachSocketRequest(operation: operation, payload: payload)
            let requestData = try JSONEncoder().encode(request)
            try HostdSocketIO.writeAll(requestData, to: fd)
            shutdown(fd, SHUT_WR)
            let responseData = try HostdSocketIO.readAll(from: fd)
            let response = try JSONDecoder().decode(HostdAttachSocketResponse.self, from: responseData)
            return response.payload
        }.value
    }
}
