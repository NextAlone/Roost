import Foundation
import MuxyShared
import RoostHostdCore
import SwiftUI

protocol RoostHostdClient: Sendable {
    var runtimeOwnershipHint: HostdRuntimeOwnership? { get }

    func runtimeOwnership() async throws -> HostdRuntimeOwnership

    func createSession(_ request: HostdCreateSessionRequest) async throws
    func attachSession(id: UUID) async throws -> HostdAttachSessionResponse
    func releaseSession(id: UUID) async throws
    func terminateSession(id: UUID) async throws
    func readSessionOutput(id: UUID, timeout: TimeInterval) async throws -> Data
    func readSessionOutputStream(id: UUID, after sequence: UInt64?, timeout: TimeInterval) async throws -> HostdOutputRead
    func writeSessionInput(id: UUID, data: Data) async throws
    func resizeSession(id: UUID, columns: UInt16, rows: UInt16) async throws
    func sendSessionSignal(id: UUID, signal: HostdSessionSignal) async throws

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
    var runtimeOwnershipHint: HostdRuntimeOwnership? { nil }

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

    func readSessionOutput(id: UUID, timeout: TimeInterval = 0) async throws -> Data {
        let error = await unsupportedRuntimeControl("read output")
        throw error
    }

    func readSessionOutputStream(id: UUID, after sequence: UInt64? = nil, timeout: TimeInterval = 0) async throws -> HostdOutputRead {
        let error = await unsupportedRuntimeControl("read output stream")
        throw error
    }

    func writeSessionInput(id: UUID, data: Data) async throws {
        let error = await unsupportedRuntimeControl("write input")
        throw error
    }

    func resizeSession(id: UUID, columns: UInt16, rows: UInt16) async throws {
        let error = await unsupportedRuntimeControl("resize")
        throw error
    }

    func sendSessionSignal(id: UUID, signal: HostdSessionSignal) async throws {
        let error = await unsupportedRuntimeControl("send signal")
        throw error
    }

    private func unsupportedRuntimeControl(_ operation: String) async -> RoostHostdClientError {
        let ownership = await (try? runtimeOwnership()) ?? .appOwnedMetadataOnly
        return .unsupportedRuntimeControl(operation: operation, ownership: ownership)
    }
}

struct LocalHostdClient: RoostHostdClient {
    private let hostd: RoostHostd

    var runtimeOwnershipHint: HostdRuntimeOwnership? { .appOwnedMetadataOnly }

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
