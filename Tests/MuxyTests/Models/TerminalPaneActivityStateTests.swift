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

    @Test("completed agent interaction acknowledges to idle")
    func completedAgentInteractionAcknowledgesToIdle() {
        let pane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .codex)
        pane.activityState = .completed

        let acknowledged = pane.acknowledgeUserInteraction()

        #expect(acknowledged == true)
        #expect(pane.activityState == .idle)
    }

    @Test("running agent interaction stays running")
    func runningAgentInteractionStaysRunning() {
        let pane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .codex)
        pane.activityState = .running

        let acknowledged = pane.acknowledgeUserInteraction()

        #expect(acknowledged == false)
        #expect(pane.activityState == .running)
    }
}
