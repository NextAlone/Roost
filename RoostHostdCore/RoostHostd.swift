import Foundation
import MuxyShared

public actor RoostHostd {
    private let store: SessionStore

    public init(databaseURL: URL = HostdStorage.defaultDatabaseURL()) async throws {
        self.store = try await SessionStore(url: databaseURL)
    }

    public func createSession(
        id: UUID,
        projectID: UUID,
        worktreeID: UUID,
        workspacePath: String,
        agentKind: AgentKind,
        command: String? = nil,
        now: Date = Date()
    ) async throws {
        let record = SessionRecord(
            id: id,
            projectID: projectID,
            worktreeID: worktreeID,
            workspacePath: workspacePath,
            agentKind: agentKind,
            command: command,
            createdAt: now,
            lastState: .running
        )
        try await store.record(record)
    }

    public func markExited(sessionID: UUID) async throws {
        try await store.update(id: sessionID, lastState: .exited)
    }

    public func listLiveSessions() async throws -> [SessionRecord] {
        try await store.listLive()
    }

    public func listAllSessions() async throws -> [SessionRecord] {
        try await store.list()
    }

    public func deleteSession(id: UUID) async throws {
        try await store.delete(id: id)
    }

    public func pruneExited() async throws {
        try await store.pruneExited()
    }

    public func markAllRunningExited() async throws {
        let live = try await store.list().filter { $0.lastState == .running }
        for record in live {
            try await store.update(id: record.id, lastState: .exited)
        }
    }
}
