import Darwin
import Dispatch
import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import Roost

@Suite("HostdDaemonSocketServer")
struct HostdDaemonSocketServerTests {
    @Test("socket daemon owns sessions across client connections")
    func socketDaemonOwnsSessionsAcrossClientConnections() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("roost-hostd-daemon-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let socketPath = "/tmp/roost-hostd-daemon-\(UUID().uuidString.prefix(8)).sock"
        let registry = try await HostdProcessRegistry(databaseURL: root.appendingPathComponent("sessions.sqlite"))
        let server = HostdDaemonSocketServer(socketPath: socketPath, registry: registry)
        server.start()
        defer {
            server.stop()
            unlink(socketPath)
        }
        try await waitForSocket(at: socketPath)

        let sessionID = UUID()
        let projectID = UUID()
        let worktreeID = UUID()
        let firstClient = XPCHostdClient(transport: HostdSocketTransport(socketPath: socketPath))
        try await firstClient.createSession(HostdCreateSessionRequest(
            id: sessionID,
            projectID: projectID,
            worktreeID: worktreeID,
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .codex,
            command: "printf ready; sleep 20"
        ))

        let secondClient = XPCHostdClient(transport: HostdSocketTransport(socketPath: socketPath))
        let live = try await secondClient.listLiveSessions()
        #expect(live.map(\.id).contains(sessionID))

        let attached = try await secondClient.attachSession(id: sessionID)
        #expect(attached.ownership == .hostdOwnedProcess)
        #expect(attached.record.id == sessionID)

        try await secondClient.terminateSession(id: sessionID)
        let remaining = try await firstClient.listLiveSessions()
        #expect(!remaining.map(\.id).contains(sessionID))
    }

    @Test("launcher rejects a daemon without runtime identity")
    func launcherRejectsDaemonWithoutRuntimeIdentity() async throws {
        let socketPath = "/tmp/roost-hostd-legacy-\(UUID().uuidString.prefix(8)).sock"
        let server = LegacyRuntimeOwnershipSocketServer(socketPath: socketPath)
        try server.start()
        defer {
            server.stop()
        }
        try await waitForSocket(at: socketPath)

        await #expect(throws: HostdDaemonLauncherError.self) {
            try await HostdDaemonLauncher.ensureRunning(socketPath: socketPath, executablePath: nil)
        }
    }

    private func waitForSocket(at path: String) async throws {
        for _ in 0 ..< 80 {
            if FileManager.default.fileExists(atPath: path) { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw HostdDaemonSocketServerTestError.socketDidNotStart
    }
}

private enum HostdDaemonSocketServerTestError: Error {
    case socketDidNotStart
}

private final class LegacyRuntimeOwnershipSocketServer: @unchecked Sendable {
    private let socketPath: String
    private let queue = DispatchQueue(label: "app.roost.tests.legacy-hostd")
    private var serverFD: CInt = -1
    private var source: DispatchSourceRead?

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() throws {
        unlink(socketPath)
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else { throw HostdDaemonSocketServerTestError.socketDidNotStart }
        try HostdSocketIO.setCloseOnExec(serverFD)

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
        guard bindResult == 0 else { throw HostdDaemonSocketServerTestError.socketDidNotStart }
        guard listen(serverFD, 8) == 0 else { throw HostdDaemonSocketServerTestError.socketDidNotStart }

        let source = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
    }

    private func acceptConnection() {
        let fd = accept(serverFD, nil, nil)
        guard fd >= 0 else { return }
        Task.detached {
            defer { close(fd) }
            let requestData = try HostdSocketIO.readAll(from: fd)
            let request = try JSONDecoder().decode(HostdAttachSocketRequest.self, from: requestData)
            let payload: Data
            if request.operation == .runtimeOwnership {
                payload = try HostdXPCCodec.success(HostdRuntimeOwnership.hostdOwnedProcess)
            } else {
                payload = HostdXPCCodec.failure("unsupported operation")
            }
            let response = HostdAttachSocketResponse(payload: payload)
            try HostdSocketIO.writeAll(try JSONEncoder().encode(response), to: fd)
        }
    }
}
