import Testing

@testable import Roost

@Suite("CursorProvider")
struct CursorProviderTests {
    @Test("uses Roost hook script name")
    func usesRoostHookScriptName() {
        #expect(CursorProvider().hookScriptName == "roost-cursor-hook")
    }
}
