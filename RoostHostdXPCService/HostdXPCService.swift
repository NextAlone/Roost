import Foundation
import RoostHostdCore

enum HostdXPCServiceRuntime: Sendable {
    case metadataOnly(databaseURL: URL)
    case hostdOwnedProcess(databaseURL: URL)

    static func fromEnvironment(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        databaseURL: URL = HostdStorage.defaultDatabaseURL()
    ) -> HostdXPCServiceRuntime {
        if let value = environment["ROOST_HOSTD_RUNTIME"] {
            return runtime(for: value, databaseURL: databaseURL) ?? .metadataOnly(databaseURL: databaseURL)
        }
        return .metadataOnly(databaseURL: databaseURL)
    }

    private static func runtime(for value: String, databaseURL: URL) -> HostdXPCServiceRuntime? {
        switch value {
        case "hostd-owned-process",
             "hostdOwnedProcess":
            return .hostdOwnedProcess(databaseURL: databaseURL)
        case "metadata-only",
             "metadataOnly",
             "":
            return .metadataOnly(databaseURL: databaseURL)
        default:
            return nil
        }
    }

    var databaseURL: URL {
        switch self {
        case let .metadataOnly(databaseURL),
             let .hostdOwnedProcess(databaseURL):
            databaseURL
        }
    }

    var ownership: HostdRuntimeOwnership {
        switch self {
        case .metadataOnly:
            .appOwnedMetadataOnly
        case .hostdOwnedProcess:
            .hostdOwnedProcess
        }
    }
}

final class HostdXPCService: NSObject, RoostHostdXPCProtocol, @unchecked Sendable {
    private let runtime: HostdXPCServiceRuntime
    private let hostdTask: Task<RoostHostd, Error>?
    private let processRegistryTask: Task<HostdProcessRegistry, Error>?

    init(
        runtime: HostdXPCServiceRuntime = .fromEnvironment(),
        processKeepalive: (any HostdProcessKeepalive)? = nil
    ) {
        self.runtime = runtime
        switch runtime {
        case let .metadataOnly(databaseURL):
            self.hostdTask = Task {
                try await RoostHostd(databaseURL: databaseURL)
            }
            self.processRegistryTask = nil
        case let .hostdOwnedProcess(databaseURL):
            let keepalive = processKeepalive ?? XPCTransactionHostdProcessKeepalive()
            self.hostdTask = nil
            self.processRegistryTask = Task {
                try await HostdProcessRegistry(databaseURL: databaseURL, keepalive: keepalive)
            }
        }
        super.init()
    }

    func runtimeOwnership(reply: @escaping @Sendable (Data) -> Void) {
        reply((try? HostdXPCCodec.success(runtime.ownership)) ?? HostdXPCCodec
            .failure("Unable to encode runtime ownership"))
    }

    func createSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdCreateSessionRequest.self, from: request)
                guard let command = request.command else {
                    throw HostdProcessRegistryError.emptyCommand
                }
                _ = try await registry.launchSession(HostdLaunchSessionRequest(
                    id: request.id,
                    projectID: request.projectID,
                    worktreeID: request.worktreeID,
                    workspacePath: request.workspacePath,
                    agentKind: request.agentKind,
                    command: command,
                    createdAt: request.createdAt,
                    environment: request.environment
                ))
                return try HostdXPCCodec.success()
            }
            return
        }
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
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request)
                try await registry.terminateSession(id: request.id)
                return try HostdXPCCodec.success()
            }
            return
        }
        respond(reply) { hostd in
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request)
            try await hostd.markExited(sessionID: request.id)
            return try HostdXPCCodec.success()
        }
    }

    func listLiveSessions(reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let records = try await registry.listLiveSessions()
                return try HostdXPCCodec.success(records)
            }
            return
        }
        respond(reply) { hostd in
            let records = try await hostd.listLiveSessions()
            return try HostdXPCCodec.success(records)
        }
    }

    func listAllSessions(reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let records = try await registry.listAllSessions()
                return try HostdXPCCodec.success(records)
            }
            return
        }
        respond(reply) { hostd in
            let records = try await hostd.listAllSessions()
            return try HostdXPCCodec.success(records)
        }
    }

    func deleteSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request)
                try await registry.deleteSession(id: request.id)
                return try HostdXPCCodec.success()
            }
            return
        }
        respond(reply) { hostd in
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request)
            try await hostd.deleteSession(id: request.id)
            return try HostdXPCCodec.success()
        }
    }

    func pruneExited(reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                try await registry.pruneExited()
                return try HostdXPCCodec.success()
            }
            return
        }
        respond(reply) { hostd in
            try await hostd.pruneExited()
            return try HostdXPCCodec.success()
        }
    }

    func markAllRunningExited(reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            reply((try? HostdXPCCodec.success()) ?? HostdXPCCodec.failure("Unable to encode reply"))
            return
        }
        respond(reply) { hostd in
            try await hostd.markAllRunningExited()
            return try HostdXPCCodec.success()
        }
    }

    func attachSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request)
                let response = try await registry.attachSession(id: request.id)
                return try HostdXPCCodec.success(response)
            }
            return
        }
        rejectRuntimeControl("attach", request: request, reply: reply)
    }

    func releaseSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request)
                try await registry.releaseSession(id: request.id)
                return try HostdXPCCodec.success()
            }
            return
        }
        rejectRuntimeControl("release", request: request, reply: reply)
    }

    func terminateSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: request)
                try await registry.terminateSession(id: request.id)
                return try HostdXPCCodec.success()
            }
            return
        }
        rejectRuntimeControl("terminate", request: request, reply: reply)
    }

    func readSessionOutput(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdReadSessionOutputRequest.self, from: request)
                let output = try await registry.readAvailableOutput(id: request.id, timeout: request.timeout)
                return try HostdXPCCodec.success(HostdReadSessionOutputResponse(data: output))
            }
            return
        }
        rejectRuntimeControl("read output", request: request, as: HostdReadSessionOutputRequest.self, reply: reply)
    }

    func readSessionOutputStream(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdReadSessionOutputStreamRequest.self, from: request)
                let output = try await registry.readSessionOutputStream(
                    id: request.id,
                    after: request.after,
                    timeout: request.timeout,
                    limit: request.limit,
                    mode: request.mode
                )
                return try HostdXPCCodec.success(HostdReadSessionOutputStreamResponse(output: output))
            }
            return
        }
        rejectRuntimeControl(
            "read output stream",
            request: request,
            as: HostdReadSessionOutputStreamRequest.self,
            reply: reply
        )
    }

    func writeSessionInput(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdWriteSessionInputRequest.self, from: request)
                try await registry.writeSessionInput(id: request.id, data: request.data)
                return try HostdXPCCodec.success()
            }
            return
        }
        rejectRuntimeControl("write input", request: request, as: HostdWriteSessionInputRequest.self, reply: reply)
    }

    func resizeSession(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdResizeSessionRequest.self, from: request)
                try await registry.resizeSession(id: request.id, columns: request.columns, rows: request.rows)
                return try HostdXPCCodec.success()
            }
            return
        }
        rejectRuntimeControl("resize", request: request, as: HostdResizeSessionRequest.self, reply: reply)
    }

    func sendSessionSignal(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        if runtime.ownership == .hostdOwnedProcess {
            respondRegistry(reply) { registry in
                let request = try HostdXPCCodec.decode(HostdSendSessionSignalRequest.self, from: request)
                try await registry.sendSessionSignal(id: request.id, signal: request.signal)
                return try HostdXPCCodec.success()
            }
            return
        }
        rejectRuntimeControl("send signal", request: request, as: HostdSendSessionSignalRequest.self, reply: reply)
    }

    private func respond(
        _ reply: @escaping @Sendable (Data) -> Void,
        _ work: @escaping @Sendable (RoostHostd) async throws -> Data
    ) {
        Task {
            do {
                guard let hostdTask else {
                    reply(HostdXPCCodec.failure("Hostd metadata runtime is unavailable"))
                    return
                }
                let hostd = try await hostdTask.value
                await reply(try work(hostd))
            } catch {
                reply(HostdXPCCodec.failure(Self.errorMessage(error)))
            }
        }
    }

    private func respondRegistry(
        _ reply: @escaping @Sendable (Data) -> Void,
        _ work: @escaping @Sendable (HostdProcessRegistry) async throws -> Data
    ) {
        Task {
            do {
                guard let processRegistryTask else {
                    reply(HostdXPCCodec.failure("Hostd process runtime is unavailable"))
                    return
                }
                let registry = try await processRegistryTask.value
                await reply(try work(registry))
            } catch {
                reply(HostdXPCCodec.failure(Self.errorMessage(error)))
            }
        }
    }

    private static func errorMessage(_ error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return String(describing: error) }
        return message
    }

    private func rejectRuntimeControl(
        _ operation: String,
        request: Data,
        reply: @escaping @Sendable (Data) -> Void
    ) {
        rejectRuntimeControl(operation, request: request, as: HostdSessionIDRequest.self, reply: reply)
    }

    private func rejectRuntimeControl(
        _ operation: String,
        request: Data,
        as type: (some Decodable).Type,
        reply: @escaping @Sendable (Data) -> Void
    ) {
        do {
            _ = try HostdXPCCodec.decode(type, from: request)
            reply(HostdXPCCodec.failure("Hostd \(operation) is unavailable in metadata-only runtime"))
        } catch {
            reply(HostdXPCCodec.failure(Self.errorMessage(error)))
        }
    }
}
