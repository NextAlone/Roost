import Foundation
import MuxyShared
import Testing

@Suite("AgentActivityState")
struct AgentActivityStateTests {
    @Test("Codable round-trips all cases")
    func codableRoundTrip() throws {
        let original = AgentActivityState.allCases
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([AgentActivityState].self, from: data)
        #expect(decoded == original)
    }

    @Test("raw values are stable")
    func rawValues() {
        #expect(AgentActivityState.running.rawValue == "running")
        #expect(AgentActivityState.needsInput.rawValue == "needsInput")
        #expect(AgentActivityState.idle.rawValue == "idle")
        #expect(AgentActivityState.completed.rawValue == "completed")
        #expect(AgentActivityState.exited.rawValue == "exited")
    }

    @Test("sidebar labels are compact")
    func sidebarLabels() {
        #expect(AgentActivityState.running.sidebarLabel == "RUN")
        #expect(AgentActivityState.needsInput.sidebarLabel == "WAIT")
        #expect(AgentActivityState.idle.sidebarLabel == "IDLE")
        #expect(AgentActivityState.completed.sidebarLabel == "DONE")
        #expect(AgentActivityState.exited.sidebarLabel == "EXIT")
    }
}
