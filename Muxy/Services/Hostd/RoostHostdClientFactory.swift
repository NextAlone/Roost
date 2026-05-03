import Foundation
import MuxyShared
import RoostHostdCore

enum RoostHostdClientFactory {
    static func make(
        xpcServiceExists: @escaping @Sendable () -> Bool = defaultXPCServiceExists,
        makeXPCClient: @escaping @Sendable () -> any RoostHostdClient = { XPCHostdClient() },
        makeLocalClient: @escaping @Sendable () async throws -> any RoostHostdClient = {
            let hostd = try await RoostHostd()
            return LocalHostdClient(hostd: hostd)
        }
    ) async -> (any RoostHostdClient)? {
        if xpcServiceExists() {
            let client = makeXPCClient()
            let ownership = try? await client.runtimeOwnership()
            if let ownership {
                return RuntimeHintHostdClient(client: client, runtimeOwnershipHint: ownership)
            }
        }
        return try? await makeLocalClient()
    }

    private static func defaultXPCServiceExists() -> Bool {
        let url = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("XPCServices", isDirectory: true)
            .appendingPathComponent("RoostHostdXPCService.xpc", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

private struct RuntimeHintHostdClient: RoostHostdClient {
    let client: any RoostHostdClient
    let runtimeOwnershipHint: HostdRuntimeOwnership?

    func runtimeOwnership() async throws -> HostdRuntimeOwnership {
        if let runtimeOwnershipHint { return runtimeOwnershipHint }
        return try await client.runtimeOwnership()
    }

    func createSession(_ request: HostdCreateSessionRequest) async throws {
        try await client.createSession(request)
    }

    func attachSession(id: UUID) async throws -> HostdAttachSessionResponse {
        try await client.attachSession(id: id)
    }

    func releaseSession(id: UUID) async throws {
        try await client.releaseSession(id: id)
    }

    func terminateSession(id: UUID) async throws {
        try await client.terminateSession(id: id)
    }

    func readSessionOutput(id: UUID, timeout: TimeInterval) async throws -> Data {
        try await client.readSessionOutput(id: id, timeout: timeout)
    }

    func writeSessionInput(id: UUID, data: Data) async throws {
        try await client.writeSessionInput(id: id, data: data)
    }

    func resizeSession(id: UUID, columns: UInt16, rows: UInt16) async throws {
        try await client.resizeSession(id: id, columns: columns, rows: rows)
    }

    func sendSessionSignal(id: UUID, signal: HostdSessionSignal) async throws {
        try await client.sendSessionSignal(id: id, signal: signal)
    }

    func markExited(sessionID: UUID) async throws {
        try await client.markExited(sessionID: sessionID)
    }

    func listLiveSessions() async throws -> [SessionRecord] {
        try await client.listLiveSessions()
    }

    func listAllSessions() async throws -> [SessionRecord] {
        try await client.listAllSessions()
    }

    func deleteSession(id: UUID) async throws {
        try await client.deleteSession(id: id)
    }

    func pruneExited() async throws {
        try await client.pruneExited()
    }

    func markAllRunningExited() async throws {
        try await client.markAllRunningExited()
    }
}
