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

        func recordedControlIDs() -> [String: UUID] {
            controlIDs
        }

        func recordedInput() -> Data? {
            lastInput
        }

        func recordedResize() -> HostdResizeSessionRequest? {
            lastResize
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
        func writeSessionInput(_ request: Data) async throws -> Data { throw Failure() }
        func resizeSession(_ request: Data) async throws -> Data { throw Failure() }
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
        try await client.writeSessionInput(id: id, data: Data("hello\n".utf8))
        try await client.resizeSession(id: id, columns: 100, rows: 40)

        let ids = await transport.recordedControlIDs()
        #expect(attach.record.id == id)
        #expect(attach.ownership == .hostdOwnedProcess)
        #expect(String(decoding: output, as: UTF8.self) == "xpc-output")
        #expect(ids["attach"] == id)
        #expect(ids["release"] == id)
        #expect(ids["terminate"] == id)
        #expect(ids["read"] == id)
        #expect(ids["write"] == id)
        #expect(ids["resize"] == id)
        #expect(await transport.recordedInput() == Data("hello\n".utf8))
        #expect(await transport.recordedResize()?.columns == 100)
        #expect(await transport.recordedResize()?.rows == 40)
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
}
