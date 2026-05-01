import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("TerminalPaneState activity")
struct TerminalPaneActivityStateTests {
    @Test("terminal panes start running")
    func terminalStartsRunning() {
        let pane = TerminalPaneState(projectPath: "/tmp/wt")

        #expect(pane.activityState == .running)
    }

    @Test("agent panes start idle")
    func agentStartsIdle() {
        let pane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .codex)

        #expect(pane.activityState == .idle)
    }
}
