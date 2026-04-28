import Foundation
import MuxyShared
import Testing

@Suite("SessionLifecycleState")
struct SessionLifecycleStateTests {
    @Test("Codable round-trips all cases")
    func codableRoundTrip() throws {
        let original = SessionLifecycleState.allCases
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([SessionLifecycleState].self, from: data)
        #expect(decoded == original)
    }

    @Test("raw values are stable")
    func rawValues() {
        #expect(SessionLifecycleState.running.rawValue == "running")
        #expect(SessionLifecycleState.exited.rawValue == "exited")
    }
}
