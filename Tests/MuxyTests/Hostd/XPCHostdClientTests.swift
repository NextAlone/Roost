import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import Roost

@Suite("XPCHostdClient")
struct XPCHostdClientTests {
    private actor FakeTransport: HostdXPCTransport {
        private var records: [SessionRecord] = []
        private var controlIDs: [String: UUID] = [:]
        private var lastInput: Data?
        private var lastResize: HostdResizeSessionRequest?
        private var lastSignal: HostdSendSessionSignalRequest?
        private var lastStreamRequest: HostdReadSessionOutputStreamRequest?

        func runtimeOwnership() async throws -> Data {
            try HostdXPCCodec.success(HostdRuntimeOwnership.appOwnedMetadataOnly)
        }

        func createSession(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdCreateSessionRequest.self, from: data)
            records.append(
                SessionRecord(
                    id: request.id,
                    projectID: request.projectID,
                    worktreeID: request.worktreeID,
                    workspacePath: request.workspacePath,
                    agentKind: request.agentKind,
                    command: request.command,
                    createdAt: request.createdAt,
                    lastState: .running
                )
            )
            return try HostdXPCCodec.success()
        }

        func markExited(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: data)
            records = records.map { record in
                if record.id != request.id { return record }
                return SessionRecord(
                    id: record.id,
                    projectID: record.projectID,
                    worktreeID: record.worktreeID,
                    workspacePath: record.workspacePath,
                    agentKind: record.agentKind,
                    command: record.command,
                    createdAt: record.createdAt,
                    lastState: .exited
                )
            }
            return try HostdXPCCodec.success()
        }

        func listLiveSessions() async throws -> Data {
            try HostdXPCCodec.success(records.filter { $0.lastState == .running })
        }

        func listAllSessions() async throws -> Data {
            try HostdXPCCodec.success(records)
        }

        func deleteSession(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: data)
            records.removeAll { $0.id == request.id }
            return try HostdXPCCodec.success()
        }

        func pruneExited() async throws -> Data {
            records.removeAll { $0.lastState == .exited }
            return try HostdXPCCodec.success()
        }

        func markAllRunningExited() async throws -> Data {
            records = records.map { record in
                SessionRecord(
                    id: record.id,
                    projectID: record.projectID,
                    worktreeID: record.worktreeID,
                    workspacePath: record.workspacePath,
                    agentKind: record.agentKind,
                    command: record.command,
                    createdAt: record.createdAt,
                    lastState: .exited
                )
            }
            return try HostdXPCCodec.success()
        }

        func attachSession(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: data)
            controlIDs["attach"] = request.id
            let record = SessionRecord(
                id: request.id,
                projectID: UUID(),
                worktreeID: UUID(),
                workspacePath: "/tmp/wt",
                agentKind: .codex,
                command: "codex",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                lastState: .running
            )
            return try HostdXPCCodec.success(HostdAttachSessionResponse(
                record: record,
                ownership: .hostdOwnedProcess
            ))
        }

        func releaseSession(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: data)
            controlIDs["release"] = request.id
            return try HostdXPCCodec.success()
        }

        func terminateSession(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdSessionIDRequest.self, from: data)
            controlIDs["terminate"] = request.id
            return try HostdXPCCodec.success()
        }

        func readSessionOutput(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdReadSessionOutputRequest.self, from: data)
            controlIDs["read"] = request.id
            return try HostdXPCCodec.success(HostdReadSessionOutputResponse(data: Data("xpc-output".utf8)))
        }

        func readSessionOutputStream(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdReadSessionOutputStreamRequest.self, from: data)
            controlIDs["stream"] = request.id
            lastStreamRequest = request
            return try HostdXPCCodec.success(HostdReadSessionOutputStreamResponse(output: HostdOutputRead(
                chunks: [HostdOutputChunk(sequence: request.after ?? 0, data: Data("xpc-stream".utf8))],
                nextSequence: (request.after ?? 0) + 10,
                truncated: false
            )))
        }

        func writeSessionInput(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdWriteSessionInputRequest.self, from: data)
            controlIDs["write"] = request.id
            lastInput = request.data
            return try HostdXPCCodec.success()
        }

        func resizeSession(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdResizeSessionRequest.self, from: data)
            controlIDs["resize"] = request.id
            lastResize = request
            return try HostdXPCCodec.success()
        }

        func sendSessionSignal(_ data: Data) async throws -> Data {
            let request = try HostdXPCCodec.decode(HostdSendSessionSignalRequest.self, from: data)
            controlIDs["signal"] = request.id
            lastSignal = request
            return try HostdXPCCodec.success()
        }

        func recordedControlIDs() -> [String: UUID] {
            controlIDs
        }

        func recordedInput() -> Data? {
            lastInput
        }

        func recordedResize() -> HostdResizeSessionRequest? {
            lastResize
        }

        func recordedSignal() -> HostdSendSessionSignalRequest? {
            lastSignal
        }

        func recordedStreamRequest() -> HostdReadSessionOutputStreamRequest? {
            lastStreamRequest
        }
    }

    private struct FailingTransport: HostdXPCTransport {
        struct Failure: Error {}

        func runtimeOwnership() async throws -> Data { throw Failure() }
        func createSession(_ request: Data) async throws -> Data { throw Failure() }
        func markExited(_ request: Data) async throws -> Data { throw Failure() }
        func listLiveSessions() async throws -> Data { throw Failure() }
        func listAllSessions() async throws -> Data { throw Failure() }
        func deleteSession(_ request: Data) async throws -> Data { throw Failure() }
        func pruneExited() async throws -> Data { throw Failure() }
        func markAllRunningExited() async throws -> Data { throw Failure() }
        func attachSession(_ request: Data) async throws -> Data { throw Failure() }
        func releaseSession(_ request: Data) async throws -> Data { throw Failure() }
        func terminateSession(_ request: Data) async throws -> Data { throw Failure() }
        func readSessionOutput(_ request: Data) async throws -> Data { throw Failure() }
        func readSessionOutputStream(_ request: Data) async throws -> Data { throw Failure() }
        func writeSessionInput(_ request: Data) async throws -> Data { throw Failure() }
        func resizeSession(_ request: Data) async throws -> Data { throw Failure() }
        func sendSessionSignal(_ request: Data) async throws -> Data { throw Failure() }
    }

    private struct HangingTransport: HostdXPCTransport {
        func runtimeOwnership() async throws -> Data { try await never() }
        func createSession(_ request: Data) async throws -> Data { try await never() }
        func markExited(_ request: Data) async throws -> Data { try await never() }
        func listLiveSessions() async throws -> Data { try await never() }
        func listAllSessions() async throws -> Data { try await never() }
        func deleteSession(_ request: Data) async throws -> Data { try await never() }
        func pruneExited() async throws -> Data { try await never() }
        func markAllRunningExited() async throws -> Data { try await never() }
        func attachSession(_ request: Data) async throws -> Data { try await never() }
        func releaseSession(_ request: Data) async throws -> Data { try await never() }
        func terminateSession(_ request: Data) async throws -> Data { try await never() }
        func readSessionOutput(_ request: Data) async throws -> Data { try await never() }
        func readSessionOutputStream(_ request: Data) async throws -> Data { try await never() }
        func writeSessionInput(_ request: Data) async throws -> Data { try await never() }
        func resizeSession(_ request: Data) async throws -> Data { try await never() }
        func sendSessionSignal(_ request: Data) async throws -> Data { try await never() }

        private func never() async throws -> Data {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return Data()
        }
    }

    @Test("creates, lists, exits, and deletes through transport")
    func roundTrip() async throws {
        let transport = FakeTransport()
        let client = XPCHostdClient(transport: transport)
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(try await client.runtimeOwnership() == .appOwnedMetadataOnly)
        try await client.createSession(HostdCreateSessionRequest(
            id: id,
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .codex,
            command: "codex",
            createdAt: createdAt
        ))
        #expect(try await client.listLiveSessions().map(\.id) == [id])
        #expect(try await client.listAllSessions().first?.createdAt == createdAt)

        try await client.markExited(sessionID: id)
        #expect(try await client.listLiveSessions().isEmpty)
        #expect(try await client.listAllSessions().first?.lastState == .exited)

        try await client.deleteSession(id: id)
        #expect(try await client.listAllSessions().isEmpty)
    }

    @Test("session control methods round-trip through transport")
    func sessionControlRoundTrip() async throws {
        let transport = FakeTransport()
        let client = XPCHostdClient(transport: transport)
        let id = UUID()

        let attach = try await client.attachSession(id: id)
        try await client.releaseSession(id: id)
        try await client.terminateSession(id: id)
        let output = try await client.readSessionOutput(id: id, timeout: 0.25)
        let stream = try await client.readSessionOutputStream(id: id, after: 12, timeout: 0.25, limit: 128)
        try await client.writeSessionInput(id: id, data: Data("hello\n".utf8))
        try await client.resizeSession(id: id, columns: 100, rows: 40)
        try await client.sendSessionSignal(id: id, signal: .interrupt)

        let ids = await transport.recordedControlIDs()
        #expect(attach.record.id == id)
        #expect(attach.ownership == .hostdOwnedProcess)
        #expect(String(decoding: output, as: UTF8.self) == "xpc-output")
        #expect(String(decoding: stream.chunks.flatMap(\.data), as: UTF8.self) == "xpc-stream")
        #expect(ids["attach"] == id)
        #expect(ids["release"] == id)
        #expect(ids["terminate"] == id)
        #expect(ids["read"] == id)
        #expect(ids["stream"] == id)
        #expect(ids["write"] == id)
        #expect(ids["resize"] == id)
        #expect(ids["signal"] == id)
        #expect(await transport.recordedStreamRequest()?.after == 12)
        #expect(await transport.recordedStreamRequest()?.timeout == 0.25)
        #expect(await transport.recordedStreamRequest()?.limit == 128)
        #expect(await transport.recordedInput() == Data("hello\n".utf8))
        #expect(await transport.recordedResize()?.columns == 100)
        #expect(await transport.recordedResize()?.rows == 40)
        #expect(await transport.recordedSignal()?.signal == .interrupt)
    }

    @Test("transport errors propagate")
    func transportErrorsPropagate() async {
        let client = XPCHostdClient(transport: FailingTransport())
        do {
            _ = try await client.runtimeOwnership()
            Issue.record("Expected transport failure to throw")
        } catch is FailingTransport.Failure {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("create session times out when transport does not reply")
    func createSessionTimesOutWhenTransportHangs() async {
        let client = XPCHostdClient(transport: HangingTransport(), requestTimeout: 0.01)

        await #expect(throws: HostdAsyncTimeoutError.self) {
            try await client.createSession(HostdCreateSessionRequest(
                id: UUID(),
                projectID: UUID(),
                worktreeID: UUID(),
                workspacePath: "/tmp/wt",
                agentKind: .codex,
                command: "codex"
            ))
        }
    }
}
