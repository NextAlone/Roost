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

    @Test("uses app config runtime when environment override is unset")
    func usesAppConfigRuntime() {
        let url = makeTempStoreURL()
        let runtime = HostdXPCServiceRuntime.fromEnvironment(
            environment: [:],
            databaseURL: url,
            configLoader: {
                RoostConfig(hostdRuntime: .hostdOwnedProcess)
            }
        )

        #expect(runtime.ownership == .hostdOwnedProcess)
        #expect(runtime.databaseURL == url)
    }

    @Test("environment runtime overrides app config runtime")
    func environmentRuntimeOverridesAppConfig() {
        let url = makeTempStoreURL()
        let runtime = HostdXPCServiceRuntime.fromEnvironment(
            environment: ["ROOST_HOSTD_RUNTIME": "metadata-only"],
            databaseURL: url,
            configLoader: {
                RoostConfig(hostdRuntime: .hostdOwnedProcess)
            }
        )

        #expect(runtime.ownership == .appOwnedMetadataOnly)
        #expect(runtime.databaseURL == url)
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

        let streamReply = await call {
            service.readSessionOutputStream(
                try HostdXPCCodec.encode(HostdReadSessionOutputStreamRequest(id: id)),
                reply: $0
            )
        }
        #expect(throws: HostdXPCError.self) {
            try HostdXPCCodec.decodeReply(HostdReadSessionOutputStreamResponse.self, from: streamReply)
        }

        let signalReply = await call {
            service.sendSessionSignal(
                try HostdXPCCodec.encode(HostdSendSessionSignalRequest(id: id, signal: .interrupt)),
                reply: $0
            )
        }
        #expect(throws: HostdXPCError.self) {
            try HostdXPCCodec.decodeEmptyReply(from: signalReply)
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

    @Test("hostd-owned mode launches with request environment")
    func hostdOwnedRuntimeRequestEnvironment() async throws {
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
            command: "printf \"$ROOST_ENV_TEST\"; sleep 5",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            environment: ["ROOST_ENV_TEST": "xpc-env"]
        )

        let createReply = await call {
            service.createSession(try HostdXPCCodec.encode(request), reply: $0)
        }
        try HostdXPCCodec.decodeEmptyReply(from: createReply)

        let outputReply = await call {
            service.readSessionOutput(
                try HostdXPCCodec.encode(HostdReadSessionOutputRequest(id: id, timeout: 1)),
                reply: $0
            )
        }
        let output = try HostdXPCCodec.decodeReply(HostdReadSessionOutputResponse.self, from: outputReply)
        let text = String(decoding: output.data, as: UTF8.self)
        #expect(text.contains("xpc-env"))

        let streamReply = await call {
            service.readSessionOutputStream(
                try HostdXPCCodec.encode(HostdReadSessionOutputStreamRequest(id: id, after: nil, timeout: 0)),
                reply: $0
            )
        }
        let stream = try HostdXPCCodec.decodeReply(HostdReadSessionOutputStreamResponse.self, from: streamReply)
        #expect(String(decoding: stream.output.chunks.flatMap(\.data), as: UTF8.self).contains("xpc-env"))

        let terminateReply = await call {
            service.terminateSession(try HostdXPCCodec.encode(HostdSessionIDRequest(id: id)), reply: $0)
        }
        try HostdXPCCodec.decodeEmptyReply(from: terminateReply)
    }

    @Test("hostd-owned mode sends interrupt signal through XPC service surface")
    func hostdOwnedRuntimeSignal() async throws {
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
            command: "exec perl -e '$SIG{INT}=sub{print \"interrupted\"; exit 0}; print \"ready\"; sleep 60'",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let createReply = await call {
            service.createSession(try HostdXPCCodec.encode(request), reply: $0)
        }
        try HostdXPCCodec.decodeEmptyReply(from: createReply)

        _ = try await readText(
            from: service,
            id: id,
            until: { $0.contains("ready") }
        )
        let signalReply = await call {
            service.sendSessionSignal(
                try HostdXPCCodec.encode(HostdSendSessionSignalRequest(id: id, signal: .interrupt)),
                reply: $0
            )
        }
        try HostdXPCCodec.decodeEmptyReply(from: signalReply)

        let text = try await readText(
            from: service,
            id: id,
            until: { $0.contains("interrupted") }
        )
        #expect(text.contains("interrupted"))
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
