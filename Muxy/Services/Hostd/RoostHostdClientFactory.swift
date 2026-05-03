import Foundation
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
            if ownership != nil {
                return client
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
