import Foundation
import MuxyShared
import SwiftUI

actor RoostHostd {
    private let store: SessionStore

    init(databaseURL: URL = HostdStorage.defaultDatabaseURL()) async throws {
        self.store = try await SessionStore(url: databaseURL)
    }

    func createSession(
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

    func markExited(sessionID: UUID) async throws {
        try await store.update(id: sessionID, lastState: .exited)
    }

    func listLiveSessions() async throws -> [SessionRecord] {
        try await store.listLive()
    }

    func listAllSessions() async throws -> [SessionRecord] {
        try await store.list()
    }

    func deleteSession(id: UUID) async throws {
        try await store.delete(id: id)
    }

    func pruneExited() async throws {
        try await store.pruneExited()
    }
}

extension EnvironmentValues {
    @Entry var roostHostd: RoostHostd?
}
