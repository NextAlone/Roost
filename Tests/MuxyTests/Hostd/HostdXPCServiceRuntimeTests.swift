import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import RoostHostdXPCService

@Suite("HostdXPCService runtime mode")
struct HostdXPCServiceRuntimeTests {
    private func makeTempStoreURL() -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
        return tmp.appendingPathComponent("sessions.sqlite")
    }

    @Test("metadata-only mode still rejects runtime control")
    func metadataOnlyRejectsRuntimeControl() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = HostdXPCService(runtime: .metadataOnly(databaseURL: url))
        let id = UUID()

        let ownership = try await decodeReply(HostdRuntimeOwnership.self) { reply in
            service.runtimeOwnership(reply: reply)
        }
        #expect(ownership == .appOwnedMetadataOnly)

        let reply = await call {
            service.attachSession(try HostdXPCCodec.encode(HostdSessionIDRequest(id: id)), reply: $0)
        }
        #expect(throws: HostdXPCError.self) {
            try HostdXPCCodec.decodeReply(HostdAttachSessionResponse.self, from: reply)
        }
    }

    @Test("hostd-owned mode launches, attaches, and terminates via XPC service surface")
    func hostdOwnedRuntimeControl() async throws {
        let url = makeTempStoreURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let service = HostdXPCService(runtime: .hostdOwnedProcess(databaseURL: url))
        let id = UUID()
        let request = HostdCreateSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: FileManager.default.temporaryDirectory.path(percentEncoded: false),
            agentKind: .terminal,
            command: "printf xpc-hostd-ready; sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let ownership = try await decodeReply(HostdRuntimeOwnership.self) { reply in
            service.runtimeOwnership(reply: reply)
        }
        #expect(ownership == .hostdOwnedProcess)

        let createReply = await call {
            service.createSession(try HostdXPCCodec.encode(request), reply: $0)
        }
        try HostdXPCCodec.decodeEmptyReply(from: createReply)

        let attached = try await decodeReply(HostdAttachSessionResponse.self) { reply in
            service.attachSession(try HostdXPCCodec.encode(HostdSessionIDRequest(id: id)), reply: reply)
        }
        #expect(attached.record.id == id)
        #expect(attached.ownership == .hostdOwnedProcess)

        let terminateReply = await call {
            service.terminateSession(try HostdXPCCodec.encode(HostdSessionIDRequest(id: id)), reply: $0)
        }
        try HostdXPCCodec.decodeEmptyReply(from: terminateReply)

        let live = try await decodeReply([SessionRecord].self) { reply in
            service.listLiveSessions(reply: reply)
        }
        #expect(live.isEmpty)
    }

    private func decodeReply<T: Decodable>(
        _ type: T.Type,
        _ body: (@escaping @Sendable (Data) -> Void) throws -> Void
    ) async throws -> T {
        let data = await call(body)
        return try HostdXPCCodec.decodeReply(type, from: data)
    }

    private func call(_ body: (@escaping @Sendable (Data) -> Void) throws -> Void) async -> Data {
        await withCheckedContinuation { continuation in
            do {
                try body { data in
                    continuation.resume(returning: data)
                }
            } catch {
                continuation.resume(returning: HostdXPCCodec.failure(String(describing: error)))
            }
        }
    }
}
