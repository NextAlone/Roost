import Foundation
import MuxyShared
import RoostHostdCore
import SwiftUI

protocol RoostHostdClient: Sendable {
    func runtimeOwnership() async throws -> HostdRuntimeOwnership

    func createSession(_ request: HostdCreateSessionRequest) async throws
    func attachSession(id: UUID) async throws -> HostdAttachSessionResponse
    func releaseSession(id: UUID) async throws
    func terminateSession(id: UUID) async throws

    func markExited(sessionID: UUID) async throws
    func listLiveSessions() async throws -> [SessionRecord]
    func listAllSessions() async throws -> [SessionRecord]
    func deleteSession(id: UUID) async throws
    func pruneExited() async throws
    func markAllRunningExited() async throws
}

enum RoostHostdClientError: LocalizedError, Sendable, Equatable {
    case unsupportedRuntimeControl(operation: String, ownership: HostdRuntimeOwnership)

    var errorDescription: String? {
        switch self {
        case let .unsupportedRuntimeControl(operation, .appOwnedMetadataOnly):
            "Hostd \(operation) is unavailable in metadata-only runtime"
        case let .unsupportedRuntimeControl(operation, .hostdOwnedProcess):
            "Hostd \(operation) is unavailable for hostd-owned runtime"
        }
    }
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

    func attachSession(id: UUID) async throws -> HostdAttachSessionResponse {
        let error = await unsupportedRuntimeControl("attach")
        throw error
    }

    func releaseSession(id: UUID) async throws {
        let error = await unsupportedRuntimeControl("release")
        throw error
    }

    func terminateSession(id: UUID) async throws {
        let error = await unsupportedRuntimeControl("terminate")
        throw error
    }

    private func unsupportedRuntimeControl(_ operation: String) async -> RoostHostdClientError {
        let ownership = await (try? runtimeOwnership()) ?? .appOwnedMetadataOnly
        return .unsupportedRuntimeControl(operation: operation, ownership: ownership)
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
