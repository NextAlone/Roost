import RoostHostdCore
import Testing

@Suite("Hostd daemon runtime identity")
struct HostdDaemonRuntimeIdentityTests {
    @Test("protocol version advances for tmux-backed agent sessions")
    func protocolVersionAdvancesForTmuxBackedAgentSessions() {
        #expect(HostdDaemonRuntimeIdentity.currentProtocolVersion == 7)
    }
}
