import SwiftUI
import Testing

@testable import Roost

@Suite("AgentReloadBanner")
struct AgentReloadBannerTests {
    @Test("exit variant shows resume and restart")
    func exitVariantShowsResumeAndRestart() {
        let model = AgentReloadBanner.Model.exit(
            agentName: "claude",
            captured: "claude --resume abc",
            onResume: {},
            onFresh: {},
            onDismiss: {}
        )
        #expect(model.primaryButtonEnabled)
        #expect(model.primaryLabel == "Resume")
        #expect(model.secondaryLabel == "Restart fresh")
    }

    @Test("exit without capture disables resume")
    func exitWithoutCaptureDisablesResume() {
        let model = AgentReloadBanner.Model.exit(
            agentName: "claude",
            captured: nil,
            onResume: {},
            onFresh: {},
            onDismiss: {}
        )
        #expect(!model.primaryButtonEnabled)
    }

    @Test("mtime variant shows reload only")
    func mtimeVariantShowsReload() {
        let model = AgentReloadBanner.Model.binaryUpdate(
            agentName: "claude",
            onReload: {},
            onDismiss: {}
        )
        #expect(model.primaryLabel == "Reload")
        #expect(model.secondaryLabel == nil)
    }
}
