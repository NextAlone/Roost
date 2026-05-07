import Foundation
import MuxyShared
import Testing

@Suite("AgentActivityEvent")
struct AgentActivityEventTests {
    @Test("encodes and decodes round-trip with all fields")
    func roundTrip() throws {
        let event = AgentActivityEvent(
            id: UUID(),
            paneID: UUID(),
            projectID: UUID(),
            worktreeID: UUID(),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            from: .running,
            to: .awaiting,
            sourceType: "claude_hook"
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(AgentActivityEvent.self, from: data)

        #expect(decoded == event)
    }

    @Test("decodes legacy events that omit projectID, worktreeID, sourceType")
    func decodesPartialLegacyEvent() throws {
        let json = """
        {
            "id": "11111111-2222-3333-4444-555555555555",
            "paneID": "66666666-7777-8888-9999-AAAAAAAAAAAA",
            "timestamp": 1700000000,
            "to": "running"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(AgentActivityEvent.self, from: json)

        #expect(decoded.from == nil)
        #expect(decoded.to == .running)
        #expect(decoded.projectID == nil)
        #expect(decoded.worktreeID == nil)
        #expect(decoded.sourceType == nil)
    }
}
