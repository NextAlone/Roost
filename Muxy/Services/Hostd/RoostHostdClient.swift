import Foundation
import MuxyShared
import SwiftUI

protocol RoostHostdClient: Sendable {
    func createSession(
        id: UUID,
        projectID: UUID,
        worktreeID: UUID,
        workspacePath: String,
        agentKind: AgentKind,
        command: String?
    ) async throws

    func markExited(sessionID: UUID) async throws
    func listLiveSessions() async throws -> [SessionRecord]
    func listAllSessions() async throws -> [SessionRecord]
    func deleteSession(id: UUID) async throws
    func pruneExited() async throws
    func markAllRunningExited() async throws
}

struct LocalHostdClient: RoostHostdClient {
    private let hostd: RoostHostd

    init(hostd: RoostHostd) {
        self.hostd = hostd
    }

    func createSession(
        id: UUID,
        projectID: UUID,
        worktreeID: UUID,
        workspacePath: String,
        agentKind: AgentKind,
        command: String?
    ) async throws {
        try await hostd.createSession(
            id: id,
            projectID: projectID,
            worktreeID: worktreeID,
            workspacePath: workspacePath,
            agentKind: agentKind,
            command: command
        )
    }

    func markExited(sessionID: UUID) async throws {
        try await hostd.markExited(sessionID: sessionID)
    }

    func listLiveSessions() async throws -> [SessionRecord] {
        try await hostd.listLiveSessions()
    }

    func listAllSessions() async throws -> [SessionRecord] {
        try await hostd.listAllSessions()
    }

    func deleteSession(id: UUID) async throws {
        try await hostd.deleteSession(id: id)
    }

    func pruneExited() async throws {
        try await hostd.pruneExited()
    }

    func markAllRunningExited() async throws {
        try await hostd.markAllRunningExited()
    }
}

extension EnvironmentValues {
    @Entry var roostHostdClient: (any RoostHostdClient)?
}
