import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("SessionHistoryStore")
struct SessionHistoryStoreTests {
    private final class StubClient: RoostHostdClient, @unchecked Sendable {
        private var sessions: [SessionRecord] = []
        private(set) var pruneCount = 0

        func setSessions(_ records: [SessionRecord]) {
            sessions = records
        }

        func createSession(id: UUID, projectID: UUID, worktreeID: UUID, workspacePath: String, agentKind: AgentKind, command: String?) async throws {}
        func markExited(sessionID: UUID) async throws {}
        func listLiveSessions() async throws -> [SessionRecord] {
            sessions.filter { $0.lastState == .running }
        }
        func listAllSessions() async throws -> [SessionRecord] {
            sessions
        }
        func deleteSession(id: UUID) async throws {}
        func pruneExited() async throws {
            pruneCount += 1
            sessions.removeAll { $0.lastState == .exited }
        }
        func markAllRunningExited() async throws {}
    }

    @Test("starts empty until refreshed")
    func startsEmpty() {
        let store = SessionHistoryStore()
        #expect(store.records.isEmpty)
    }

    @Test("refresh populates records via client")
    func refreshPopulates() async throws {
        let stub = StubClient()
        let record = SessionRecord(
            id: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .claudeCode,
            command: "claude",
            createdAt: Date(),
            lastState: .exited
        )
        stub.setSessions([record])
        let store = SessionHistoryStore(client: stub)
        await store.refresh()
        #expect(store.records.count == 1)
        #expect(store.records.first?.agentKind == .claudeCode)
    }

    @Test("prune calls client + refreshes")
    func prunes() async throws {
        let stub = StubClient()
        let exited = SessionRecord(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/a", agentKind: .terminal, command: nil, createdAt: Date(), lastState: .exited)
        let live = SessionRecord(id: UUID(), projectID: UUID(), worktreeID: UUID(), workspacePath: "/tmp/b", agentKind: .terminal, command: nil, createdAt: Date(), lastState: .running)
        stub.setSessions([exited, live])
        let store = SessionHistoryStore(client: stub)
        await store.refresh()
        #expect(store.records.count == 2)
        await store.prune()
        #expect(stub.pruneCount == 1)
        #expect(store.records.count == 1)
        #expect(store.records.first?.lastState == .running)
    }
}
