import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("TerminalPaneState")
struct TerminalPaneStateTests {
    @Test("new reload fields default to clean state")
    func newReloadFieldsDefaultToCleanState() {
        let state = TerminalPaneState(projectPath: "/tmp/wt")

        #expect(state.capturedResumeCommand == nil)
        #expect(state.agentBinaryPath == nil)
        #expect(state.agentBinaryMTime == nil)
        #expect(state.binaryUpdateDetected == false)
        #expect(state.exitBannerDismissed == false)
        #expect(state.mtimeBannerDismissed == false)
    }

    @Test("sessionID is set on construction")
    func sessionIDIsSet() {
        let id = UUID()
        let state = TerminalPaneState(sessionID: id, projectPath: "/tmp/wt")

        #expect(state.sessionID == id)
    }
}
