import Foundation
import MuxyShared
import Testing

@Suite("SessionRecord")
struct SessionRecordTests {
    @Test("Codable round-trip preserves all fields")
    func roundTrip() throws {
        let id = UUID()
        let projectID = UUID()
        let worktreeID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = SessionRecord(
            id: id,
            projectID: projectID,
            worktreeID: worktreeID,
            workspacePath: "/Users/me/repo/wt",
            agentKind: .claudeCode,
            command: "claude",
            createdAt: createdAt,
            lastState: .running
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
        #expect(decoded.id == id)
        #expect(decoded.projectID == projectID)
        #expect(decoded.worktreeID == worktreeID)
        #expect(decoded.workspacePath == "/Users/me/repo/wt")
        #expect(decoded.agentKind == .claudeCode)
        #expect(decoded.command == "claude")
        #expect(decoded.createdAt == createdAt)
        #expect(decoded.lastState == .running)
    }

    @Test("nil command round-trips")
    func nilCommand() throws {
        let original = SessionRecord(
            id: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            workspacePath: "/tmp/wt",
            agentKind: .terminal,
            command: nil,
            createdAt: Date(),
            lastState: .running
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)
        #expect(decoded.command == nil)
    }
}
