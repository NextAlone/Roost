import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("RoostHostd")
struct RoostHostdTests {
    private func makeTempStoreURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
        return tmp.appendingPathComponent("sessions.sqlite")
    }

    @Test("createSession persists a running record")
    func createSession() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let hostd = try await RoostHostd(databaseURL: url)
        let id = UUID()
        try await hostd.createSession(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .claudeCode,
            command: "claude"
        )
        let live = try await hostd.listLiveSessions()
        #expect(live.count == 1)
        #expect(live.first?.id == id)
        #expect(live.first?.lastState == .running)
    }

    @Test("markExited flips lastState")
    func markExited() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let hostd = try await RoostHostd(databaseURL: url)
        let id = UUID()
        try await hostd.createSession(id: id, projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/wt", agentKind: .codex, command: "codex")
        try await hostd.markExited(sessionID: id)
        let live = try await hostd.listLiveSessions()
        #expect(live.isEmpty)
        let all = try await hostd.listAllSessions()
        #expect(all.count == 1)
        #expect(all.first?.lastState == .exited)
    }
}
