import MuxyShared
import Testing

@testable import Roost

@Suite("AgentActivityStatusPulseStyle")
struct AgentActivityStatusPulseStyleTests {
    @Test("only active attention states breathe")
    func onlyActiveAttentionStatesBreathe() {
        #expect(AgentActivityStatusPulseStyle(state: .idle).breathes == false)
        #expect(AgentActivityStatusPulseStyle(state: .exited).breathes == false)
        #expect(AgentActivityStatusPulseStyle(state: .running).breathes == true)
        #expect(AgentActivityStatusPulseStyle(state: .needsInput).breathes == true)
        #expect(AgentActivityStatusPulseStyle(state: .completed).breathes == true)
    }

    @Test("breathing states share one cadence")
    func breathingStatesShareOneCadence() {
        let durations = [
            AgentActivityStatusPulseStyle(state: .running).duration,
            AgentActivityStatusPulseStyle(state: .needsInput).duration,
            AgentActivityStatusPulseStyle(state: .completed).duration,
        ]

        #expect(Set(durations).count == 1)
        #expect(durations.first == 1.24)
    }

    @Test("expanded diameters fit inside the fixed badge circle")
    func expandedDiametersFitInsideFixedBadgeCircle() {
        for state in AgentActivityState.allCases {
            let style = AgentActivityStatusPulseStyle(state: state)
            #expect(style.expandedDiameter <= AgentActivityStatusBadgeLayout.diameter)
            #expect(style.restingDiameter <= style.expandedDiameter)
        }
    }
}
