import Foundation
import MuxyShared
import RoostHostdCore
import Testing

@Suite("HostdXPCCodec")
struct HostdXPCCodecTests {
    @Test("request round-trips through shared XPC schema")
    func requestRoundTrip() throws {
        let original = HostdCreateSessionRequest(
            id: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .codex,
            command: "codex"
        )
        let data = try HostdXPCCodec.encode(original)
        let decoded = try HostdXPCCodec.decode(HostdCreateSessionRequest.self, from: data)
        #expect(decoded == original)
    }

    @Test("success reply unwraps payload")
    func successPayload() throws {
        let record = SessionRecord(
            id: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .terminal,
            command: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastState: .running
        )
        let reply = try HostdXPCCodec.success([record])
        let decoded = try HostdXPCCodec.decodeReply([SessionRecord].self, from: reply)
        #expect(decoded == [record])
    }

    @Test("attach response round-trips through shared XPC schema")
    func attachResponseRoundTrip() throws {
        let record = SessionRecord(
            id: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .codex,
            command: "codex",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastState: .running
        )
        let original = HostdAttachSessionResponse(record: record, ownership: .hostdOwnedProcess)
        let data = try HostdXPCCodec.encode(original)
        let decoded = try HostdXPCCodec.decode(HostdAttachSessionResponse.self, from: data)
        #expect(decoded == original)
    }

    @Test("failure reply throws the remote message")
    func failureReply() throws {
        let reply = HostdXPCCodec.failure("no session")
        do {
            try HostdXPCCodec.decodeEmptyReply(from: reply)
            Issue.record("Expected failure reply to throw")
        } catch HostdXPCError.errorReply(let message) {
            #expect(message == "no session")
        }
    }
}
