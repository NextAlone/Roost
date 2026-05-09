import SwiftUI
import Testing

@testable import Roost

@Suite("AgentReloadBanner")
struct AgentReloadBannerTests {
    @Test("exit variant shows reload primary")
    func exitVariantShowsReload() {
        let model = AgentReloadBanner.Model.exit(
            agentName: "claude",
            captured: "claude --resume abc",
            onResume: {},
            onDismiss: {}
        )
        #expect(model.primaryButtonEnabled)
        #expect(model.primaryLabel == "Reload Agent")
    }

    @Test("exit without capture disables reload")
    func exitWithoutCaptureDisablesReload() {
        let model = AgentReloadBanner.Model.exit(
            agentName: "claude",
            captured: nil,
            onResume: {},
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
    }
}
