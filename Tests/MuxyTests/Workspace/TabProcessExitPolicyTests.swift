import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("TabProcessExitPolicy")
struct TabProcessExitPolicyTests {
    @Test("hostd owned attach helper exit does not represent agent exit")
    func hostdOwnedAttachHelperExitDoesNotRepresentAgentExit() {
        let pane = TerminalPaneState(
            projectPath: "/tmp",
            title: "Codex",
            startupCommand: "codex",
            agentKind: .codex,
            hostdRuntimeOwnership: .hostdOwnedProcess
        )

        #expect(TabProcessExitPolicy.representsPaneSessionExit(pane) == false)
        #expect(TabProcessExitPolicy.shouldForceCloseTabAfterPaneSessionExit(pane) == false)
    }

    @Test("app owned terminal exit still represents pane exit")
    func appOwnedTerminalExitStillRepresentsPaneExit() {
        let pane = TerminalPaneState(
            projectPath: "/tmp",
            title: "Terminal",
            agentKind: .terminal,
            hostdRuntimeOwnership: .appOwnedMetadataOnly
        )

        #expect(TabProcessExitPolicy.representsPaneSessionExit(pane) == true)
        #expect(TabProcessExitPolicy.shouldForceCloseTabAfterPaneSessionExit(pane) == true)
    }
}
