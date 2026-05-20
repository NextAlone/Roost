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

    func interruptSession(_ request: Data) async throws -> Data {
        try await call(.interruptSession, payload: request)
    }

    func waitForSessionExit(_ request: Data) async throws -> Data {
        try await call(.waitForSessionExit, payload: request)
    }

    func sendTmuxKeys(_ request: Data) async throws -> Data {
        try await call(.sendTmuxKeys, payload: request)
    }

    func detectAgentActivity(_ request: Data) async throws -> Data {
        try await call(.detectAgentActivity, payload: request)
    }

    func subscribeAgentActivity(subscriptions: [UUID: String]) -> AsyncThrowingStream<HostdAgentActivityEvent, Error> {
        let socketPath = self.socketPath
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let payload = try JSONEncoder().encode(HostdSubscribeAgentActivityRequest(subscriptions: subscriptions))
                    let fd = try HostdSocketIO.connect(path: socketPath)
                    let req = HostdAttachSocketRequest(operation: .subscribeAgentActivity, payload: payload)
                    try HostdSocketIO.writeAll(try JSONEncoder().encode(req), to: fd)
                    shutdown(fd, SHUT_WR)
                    var buf = Data()
                    let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
                    source.setEventHandler {
                        var tmp = [UInt8](repeating: 0, count: 4096)
                        let n = read(fd, &tmp, tmp.count)
                        if n <= 0 { source.cancel()
                            continuation.finish()
                            return
                        }
                        buf.append(contentsOf: tmp[0 ..< n])
                        while let nl = buf.firstIndex(of: 0x0A) {
                            let line = Data(buf[buf.startIndex ..< nl])
                            buf = Data(buf[buf.index(after: nl)...])
                            if let event = try? JSONDecoder().decode(HostdAgentActivityEvent.self, from: line) {
                                continuation.yield(event)
                            }
                        }
                    }
                    source.setCancelHandler { close(fd)
                        _ = source
                    }
                    source.resume()
                    continuation.onTermination = { _ in source.cancel() }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func call(_ operation: HostdAttachSocketOperation, payload: Data = Data()) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await self.doCall(operation, payload: payload) }
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                throw HostdSocketIOError.readFailed("timeout")
            }
            let result = try await group.next()
            group.cancelAll()
            guard let result else { throw HostdSocketIOError.readFailed("timeout") }
            return result
        }
    }

    private func doCall(_ operation: HostdAttachSocketOperation, payload: Data) async throws -> Data {
        let socketPath = self.socketPath
        let fd = try HostdSocketIO.connect(path: socketPath)
        defer { close(fd) }
        let request = HostdAttachSocketRequest(operation: operation, payload: payload)
        let requestData = try JSONEncoder().encode(request)
        try HostdSocketIO.writeAll(requestData, to: fd)
        shutdown(fd, SHUT_WR)
        let responseData = try await HostdSocketIO.readAllAsync(from: fd)
        let response = try JSONDecoder().decode(HostdAttachSocketResponse.self, from: responseData)
        return response.payload
    }
}
