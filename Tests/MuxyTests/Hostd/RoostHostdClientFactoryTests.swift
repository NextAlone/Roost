import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import Roost

@Suite("RoostHostdClientFactory")
struct RoostHostdClientFactoryTests {
    private struct FakeClient: RoostHostdClient {
        let ownership: HostdRuntimeOwnership
        let runtimeFails: Bool
        var runtimeOwnershipHint: HostdRuntimeOwnership? { ownership }

        func runtimeOwnership() async throws -> HostdRuntimeOwnership {
            if runtimeFails { throw HostdXPCError.errorReply("unavailable") }
            return ownership
        }

        func createSession(_ request: HostdCreateSessionRequest) async throws {}
        func markExited(sessionID: UUID) async throws {}
        func listLiveSessions() async throws -> [SessionRecord] { [] }
        func listAllSessions() async throws -> [SessionRecord] { [] }
        func deleteSession(id: UUID) async throws {}
        func pruneExited() async throws {}
        func markAllRunningExited() async throws {}
    }

    @Test("uses XPC client when bundled service is healthy")
    func usesXPCWhenAvailable() async throws {
        let client = await RoostHostdClientFactory.make(
            xpcServiceExists: { true },
            makeXPCClient: { FakeClient(ownership: .appOwnedMetadataOnly, runtimeFails: false) },
            makeLocalClient: { FakeClient(ownership: .hostdOwnedProcess, runtimeFails: false) }
        )
        #expect(try await client?.runtimeOwnership() == .appOwnedMetadataOnly)
        #expect(client?.runtimeOwnershipHint == .appOwnedMetadataOnly)
    }

    @Test("uses local client when service bundle is missing")
    func usesLocalWhenMissing() async throws {
        let client = await RoostHostdClientFactory.make(
            xpcServiceExists: { false },
            makeXPCClient: { FakeClient(ownership: .hostdOwnedProcess, runtimeFails: false) },
            makeLocalClient: { FakeClient(ownership: .appOwnedMetadataOnly, runtimeFails: false) }
        )
        #expect(try await client?.runtimeOwnership() == .appOwnedMetadataOnly)
    }

    @Test("falls back to local when XPC runtime check fails")
    func fallsBackWhenXPCFails() async throws {
        let client = await RoostHostdClientFactory.make(
            xpcServiceExists: { true },
            makeXPCClient: { FakeClient(ownership: .hostdOwnedProcess, runtimeFails: true) },
            makeLocalClient: { FakeClient(ownership: .appOwnedMetadataOnly, runtimeFails: false) }
        )
        #expect(try await client?.runtimeOwnership() == .appOwnedMetadataOnly)
        #expect(client?.runtimeOwnershipHint == .appOwnedMetadataOnly)
    }

    @Test("healthy XPC client preserves runtime hint")
    func xpcClientPreservesRuntimeHint() async throws {
        let client = await RoostHostdClientFactory.make(
            xpcServiceExists: { true },
            makeXPCClient: { FakeClient(ownership: .hostdOwnedProcess, runtimeFails: false) },
            makeLocalClient: { FakeClient(ownership: .appOwnedMetadataOnly, runtimeFails: false) }
        )
        #expect(client?.runtimeOwnershipHint == .hostdOwnedProcess)
    }
}
