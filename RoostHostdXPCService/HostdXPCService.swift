import Foundation
import RoostHostdCore

final class HostdXPCService: NSObject, RoostHostdXPCProtocol, @unchecked Sendable {
    private let hostdTask: Task<RoostHostd, Error>

    override init() {
        self.hostdTask = Task {
            try await RoostHostd()
        }
        super.init()
    }

    func runtimeOwnership(reply: @escaping @Sendable (Data) -> Void) {
        reply((try? HostdXPCCodec.success(HostdRuntimeOwnership.appOwnedMetadataOnly)) ?? HostdXPCCodec
            .failure("Unable to encode runtime ownership"))
    }

    func createSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        respond(reply) { hostd in
            let request = try HostdXPCCodec.decode(HostdCreateSessionRequest.self, from: request)
            try await hostd.createSession(
                id: request.id,
                projectID: request.projectID,
                worktreeID: request.worktreeID,
                workspacePath: request.workspacePath,
                agentKind: request.agentKind,
                command: request.command,
                now: request.createdAt
            )
            return try HostdXPCCodec.success()
        }
    }

    func markExited(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        respond(reply) { hostd in
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request)
            try await hostd.markExited(sessionID: request.id)
            return try HostdXPCCodec.success()
        }
    }

    func listLiveSessions(reply: @escaping @Sendable (Data) -> Void) {
        respond(reply) { hostd in
            let records = try await hostd.listLiveSessions()
            return try HostdXPCCodec.success(records)
        }
    }

    func listAllSessions(reply: @escaping @Sendable (Data) -> Void) {
        respond(reply) { hostd in
            let records = try await hostd.listAllSessions()
            return try HostdXPCCodec.success(records)
        }
    }

    func deleteSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        respond(reply) { hostd in
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request)
            try await hostd.deleteSession(id: request.id)
            return try HostdXPCCodec.success()
        }
    }

    func pruneExited(reply: @escaping @Sendable (Data) -> Void) {
        respond(reply) { hostd in
            try await hostd.pruneExited()
            return try HostdXPCCodec.success()
        }
    }

    func markAllRunningExited(reply: @escaping @Sendable (Data) -> Void) {
        respond(reply) { hostd in
            try await hostd.markAllRunningExited()
            return try HostdXPCCodec.success()
        }
    }

    func attachSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        rejectRuntimeControl("attach", request: request, reply: reply)
    }

    func releaseSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        rejectRuntimeControl("release", request: request, reply: reply)
    }

    func terminateSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        rejectRuntimeControl("terminate", request: request, reply: reply)
    }

    private func respond(
        _ reply: @escaping @Sendable (Data) -> Void,
        _ work: @escaping @Sendable (RoostHostd) async throws -> Data
    ) {
        Task {
            do {
                let hostd = try await hostdTask.value
                await reply(try work(hostd))
            } catch {
                reply(HostdXPCCodec.failure(String(describing: error)))
            }
        }
    }

    private func rejectRuntimeControl(
        _ operation: String,
        request: Data,
        reply: @escaping @Sendable (Data) -> Void
    ) {
        do {
            _ = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request)
            reply(HostdXPCCodec.failure("Hostd \(operation) is unavailable in metadata-only runtime"))
        } catch {
            reply(HostdXPCCodec.failure(String(describing: error)))
        }
    }
}
