import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import Roost

@Suite("LocalHostdClient")
struct RoostHostdClientTests {
    private func makeTempStoreURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
        return tmp.appendingPathComponent("sessions.sqlite")
    }

    @Test("create + listLive round-trip via client")
    func createAndList() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let hostd = try await RoostHostd(databaseURL: url)
        let client: any RoostHostdClient = LocalHostdClient(hostd: hostd)

        let id = UUID()
        try await client.createSession(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .claudeCode,
            command: "claude"
        )
        let live = try await client.listLiveSessions()
        #expect(live.count == 1)
        #expect(live.first?.id == id)
    }

    @Test("markExited via client flips record state")
    func markExited() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let hostd = try await RoostHostd(databaseURL: url)
        let client: any RoostHostdClient = LocalHostdClient(hostd: hostd)

        let id = UUID()
        try await client.createSession(id: id, projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/wt", agentKind: .codex, command: "codex")
        try await client.markExited(sessionID: id)
        let all = try await client.listAllSessions()
        #expect(all.first?.lastState == .exited)
    }

    @Test("markAllRunningExited flips all live records")
    func markAllRunning() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let hostd = try await RoostHostd(databaseURL: url)
        let client: any RoostHostdClient = LocalHostdClient(hostd: hostd)

        try await client.createSession(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/a", agentKind: .terminal, command: nil)
        try await client.createSession(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/b", agentKind: .terminal, command: nil)
        let liveBefore = try await client.listLiveSessions()
        #expect(liveBefore.count == 2)

        try await client.markAllRunningExited()
        let liveAfter = try await client.listLiveSessions()
        #expect(liveAfter.isEmpty)
    }

    @Test("metadata-only client rejects runtime session control")
    func metadataOnlyRejectsRuntimeControl() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let hostd = try await RoostHostd(databaseURL: url)
        let client: any RoostHostdClient = LocalHostdClient(hostd: hostd)
        let id = UUID()

        await expectUnsupported {
            _ = try await client.attachSession(id: id)
        }
        await expectUnsupported {
            try await client.releaseSession(id: id)
        }
        await expectUnsupported {
            try await client.terminateSession(id: id)
        }
        await expectUnsupported {
            _ = try await client.readSessionOutput(id: id, timeout: 0)
        }
        await expectUnsupported {
            try await client.writeSessionInput(id: id, data: Data("input".utf8))
        }
        await expectUnsupported {
            try await client.resizeSession(id: id, columns: 80, rows: 24)
        }
    }

    private func expectUnsupported(_ work: () async throws -> Void) async {
        do {
            try await work()
            Issue.record("Expected metadata-only runtime control to throw")
        } catch let error as RoostHostdClientError {
            #expect(error.errorDescription?.contains("metadata-only") == true)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
