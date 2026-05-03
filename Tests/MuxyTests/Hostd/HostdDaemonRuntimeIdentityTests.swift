import RoostHostdCore
import Testing

@Suite("Hostd daemon runtime identity")
struct HostdDaemonRuntimeIdentityTests {
    @Test("protocol version advances for stream end signaling")
    func protocolVersionAdvancesForStreamEndSignaling() {
        #expect(HostdDaemonRuntimeIdentity.currentProtocolVersion == 6)
    }
}
