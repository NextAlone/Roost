import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("PaneTabStrip snapshots")
struct PaneTabStripSnapshotTests {
    @Test("agent tabs expose activity state for their icon")
    func agentTabsExposeActivityStateForIcon() {
        let pane = TerminalPaneState(projectPath: "/tmp/repo", agentKind: .codex)
        pane.activityState = .needsInput
        let tab = TerminalTab(pane: pane)

        let snapshot = PaneTabStrip.snapshots(from: [tab])[0]

        #expect(snapshot.agentKind == .codex)
        #expect(snapshot.agentActivityStateForIcon == .needsInput)
    }

    @Test("terminal tabs keep the terminal icon")
    func terminalTabsKeepTerminalIcon() {
        let tab = TerminalTab(pane: TerminalPaneState(projectPath: "/tmp/repo"))

        let snapshot = PaneTabStrip.snapshots(from: [tab])[0]

        #expect(snapshot.agentKind == .terminal)
        #expect(snapshot.agentActivityStateForIcon == nil)
    }

    @Test("agent tab status icon reserves the shared badge footprint")
    func agentTabStatusIconReservesSharedBadgeFootprint() {
        #expect(PaneTabStripLayout.agentActivityStatusIconWidth == AgentActivityStatusBadgeLayout.diameter)
        #expect(PaneTabStripLayout.agentActivityStatusIconHeight == AgentActivityStatusBadgeLayout.height)
    }
}
