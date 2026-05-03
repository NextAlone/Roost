import Darwin
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
