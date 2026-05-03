import Foundation
import Darwin
import MuxyShared
import RoostHostdCore
import Testing

@testable import Roost

@MainActor
@Suite("HostdAttachSocketServer")
struct HostdAttachSocketServerTests {
    @Test("socket request forwards attach requests through installed hostd client")
    func socketRequestForwardsAttachRequests() async throws {
        let sessionID = UUID()
        let client = EndpointBrokerRecordingHostdClient()
        let server = HostdAttachSocketServer(socketPath: "/tmp/unused.sock", client: client)
        let reply = try await server.handle(HostdAttachSocketRequest(
            operation: .attachSession,
            payload: try HostdXPCCodec.encode(HostdSessionIDRequest(id: sessionID))
        ))
        let response = try HostdXPCCodec.decodeReply(HostdAttachSessionResponse.self, from: reply.payload)

        #expect(response.record.id == sessionID)
        #expect(client.attachedSessionIDs() == [sessionID])
    }

    @Test("socket listener forwards attach requests through installed hostd client")
    func socketListenerForwardsAttachRequests() async throws {
        let sessionID = UUID()
        let socketPath = "/tmp/roost-hostd-\(UUID().uuidString.prefix(8)).sock"
        let client = EndpointBrokerRecordingHostdClient()
        let server = HostdAttachSocketServer(socketPath: socketPath, client: client)
        server.start()
        defer {
            server.stop()
            unlink(socketPath)
        }

        try await waitForSocket(at: socketPath)
        let request = HostdAttachSocketRequest(
            operation: .attachSession,
            payload: try HostdXPCCodec.encode(HostdSessionIDRequest(id: sessionID))
        )
        let reply = try send(request, to: socketPath)
        let response = try HostdXPCCodec.decodeReply(HostdAttachSessionResponse.self, from: reply.payload)

        #expect(response.record.id == sessionID)
        #expect(client.attachedSessionIDs() == [sessionID])
    }

    private func waitForSocket(at path: String) async throws {
        for _ in 0 ..< 50 {
            if FileManager.default.fileExists(atPath: path) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw HostdAttachSocketTestError.socketFailed("Socket did not start at \(path)")
    }

    private func send(_ request: HostdAttachSocketRequest, to socketPath: String) throws -> HostdAttachSocketResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw HostdAttachSocketTestError.socketFailed(String(cString: strerror(errno)))
        }
        defer {
            close(fd)
        }

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
            throw HostdAttachSocketTestError.socketFailed(String(cString: strerror(errno)))
        }

        let data = try JSONEncoder().encode(request)
        try writeAll(data, to: fd)
        shutdown(fd, SHUT_WR)
        let responseData = try readAll(from: fd)
        return try JSONDecoder().decode(HostdAttachSocketResponse.self, from: responseData)
    }

    private func writeAll(_ data: Data, to fd: Int32) throws {
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
            if count == -1, errno == EINTR {
                continue
            }
            throw HostdAttachSocketTestError.writeFailed(String(cString: strerror(errno)))
        }
    }

    private func readAll(from fd: Int32) throws -> Data {
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
            throw HostdAttachSocketTestError.readFailed(String(cString: strerror(errno)))
        }
    }
}

private enum HostdAttachSocketTestError: Error {
    case socketFailed(String)
    case writeFailed(String)
    case readFailed(String)
}

private final class EndpointBrokerRecordingHostdClient: RoostHostdClient, @unchecked Sendable {
    private let lock = NSLock()
    private var attachIDs: [UUID] = []
    var runtimeOwnershipHint: HostdRuntimeOwnership? { .hostdOwnedProcess }

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        .hostdOwnedProcess
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {}

    func attachSession(id: UUID) async throws -> HostdAttachSessionResponse {
        let count = lock.withLock {
            attachIDs.append(id)
            return attachIDs.count
        }
        return HostdAttachSessionResponse(
            record: SessionRecord(
                id: id,
                projectID: UUID(),
                worktreeID: UUID(),
                workspacePath: "/tmp",
                agentKind: .codex,
                command: "codex",
                createdAt: Date(),
                lastState: .running
            ),
            ownership: .hostdOwnedProcess,
            attachedClientCount: count
        )
    }

    func releaseSession(id: UUID) async throws {}
    func terminateSession(id: UUID) async throws {}
    func readSessionOutput(id: UUID, timeout: TimeInterval) async throws -> Data { Data() }
    func readSessionOutputStream(
        id: UUID,
        after sequence: UInt64?,
        timeout: TimeInterval,
        limit: Int?,
        mode: HostdOutputStreamReadMode
    ) async throws -> HostdOutputRead {
        HostdOutputRead(chunks: [], nextSequence: sequence ?? 0, truncated: false)
    }
    func writeSessionInput(id: UUID, data: Data) async throws {}
    func resizeSession(id: UUID, columns: UInt16, rows: UInt16) async throws {}
    func sendSessionSignal(id: UUID, signal: HostdSessionSignal) async throws {}
    func markExited(sessionID: UUID) async throws {}
    func listLiveSessions() async throws -> [SessionRecord] { [] }
    func listAllSessions() async throws -> [SessionRecord] { [] }
    func deleteSession(id: UUID) async throws {}
    func pruneExited() async throws {}
    func markAllRunningExited() async throws {}

    func attachedSessionIDs() -> [UUID] {
        lock.withLock { attachIDs }
    }
}
