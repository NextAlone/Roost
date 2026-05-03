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

        let outputReply = await call {
            service.readSessionOutput(try HostdXPCCodec.encode(HostdReadSessionOutputRequest(id: id)), reply: $0)
        }
        #expect(throws: HostdXPCError.self) {
            try HostdXPCCodec.decodeReply(HostdReadSessionOutputResponse.self, from: outputReply)
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

    @Test("hostd-owned mode reads output, writes input, and resizes PTY")
    func hostdOwnedRuntimeIO() async throws {
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
            command: "read line; stty size; printf \"input:%s\" \"$line\"; sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let createReply = await call {
            service.createSession(try HostdXPCCodec.encode(request), reply: $0)
        }
        try HostdXPCCodec.decodeEmptyReply(from: createReply)

        let resizeReply = await call {
            service.resizeSession(try HostdXPCCodec.encode(HostdResizeSessionRequest(id: id, columns: 100, rows: 40)), reply: $0)
        }
        try HostdXPCCodec.decodeEmptyReply(from: resizeReply)

        let writeReply = await call {
            service.writeSessionInput(try HostdXPCCodec.encode(HostdWriteSessionInputRequest(id: id, data: Data("hello\n".utf8))), reply: $0)
        }
        try HostdXPCCodec.decodeEmptyReply(from: writeReply)

        let text = try await readText(
            from: service,
            id: id,
            until: { $0.contains("40 100") && $0.contains("input:hello") }
        )
        #expect(text.contains("40 100"))
        #expect(text.contains("input:hello"))

        let terminateReply = await call {
            service.terminateSession(try HostdXPCCodec.encode(HostdSessionIDRequest(id: id)), reply: $0)
        }
        try HostdXPCCodec.decodeEmptyReply(from: terminateReply)
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

    private func readText(
        from service: HostdXPCService,
        id: UUID,
        until matches: (String) -> Bool
    ) async throws -> String {
        let deadline = Date().addingTimeInterval(2)
        var text = ""
        repeat {
            let output = try await decodeReply(HostdReadSessionOutputResponse.self) { reply in
                service.readSessionOutput(
                    try HostdXPCCodec.encode(HostdReadSessionOutputRequest(id: id, timeout: 0.25)),
                    reply: reply
                )
            }
            text += String(decoding: output.data, as: UTF8.self)
        } while !matches(text) && Date() < deadline
        return text
    }
}
