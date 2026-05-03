import Foundation
import MuxyShared
import RoostHostdCore
import SwiftUI

protocol RoostHostdClient: Sendable {
    func runtimeOwnership() async throws -> HostdRuntimeOwnership

    func createSession(_ request: HostdCreateSessionRequest) async throws

    func markExited(sessionID: UUID) async throws
    func listLiveSessions() async throws -> [SessionRecord]
    func listAllSessions() async throws -> [SessionRecord]
    func deleteSession(id: UUID) async throws
    func pruneExited() async throws
    func markAllRunningExited() async throws
}

extension RoostHostdClient {
    func createSession(
        id: UUID,
        projectID: UUID,
        worktreeID: UUID,
        workspacePath: String,
        agentKind: AgentKind,
        command: String?
    ) async throws {
        try await createSession(HostdCreateSessionRequest(
            id: id,
            projectID: projectID,
            worktreeID: worktreeID,
            workspacePath: workspacePath,
            agentKind: agentKind,
            command: command
        ))
    }
}

struct LocalHostdClient: RoostHostdClient {
    private let hostd: RoostHostd

    init(hostd: RoostHostd) {
        self.hostd = hostd
    }

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        .appOwnedMetadataOnly
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {
        try await hostd.createSession(
            id: request.id,
            projectID: request.projectID,
            worktreeID: request.worktreeID,
            workspacePath: request.workspacePath,
            agentKind: request.agentKind,
            command: request.command,
            now: request.createdAt
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
