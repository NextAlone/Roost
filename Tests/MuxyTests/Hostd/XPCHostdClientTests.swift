import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@testable import Roost

@Suite("XPCHostdClient")
struct XPCHostdClientTests {
    private actor FakeTransport: HostdXPCTransport {
        private var records: [SessionRecord] = []

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
