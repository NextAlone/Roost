import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("SidebarAgentActivityResolver")
struct SidebarAgentActivityResolverTests {
    @Test("returns active agent state")
    func activeAgentState() {
        let terminal = TerminalTab(pane: TerminalPaneState(projectPath: "/tmp/wt"))
        let agentPane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .codex)
        agentPane.activityState = .running
        let agent = TerminalTab(pane: agentPane)

        let state = SidebarAgentActivityResolver.activityState(
            tabs: [terminal, agent],
            activeTabID: agent.id
        )

        #expect(state == .running)
    }

    @Test("prioritizes needs input across inactive agent tabs")
    func prioritizesNeedsInput() {
        let runningPane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .codex)
        runningPane.activityState = .running
        let waitingPane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .claudeCode)
        waitingPane.activityState = .needsInput

        let state = SidebarAgentActivityResolver.activityState(
            tabs: [TerminalTab(pane: runningPane), TerminalTab(pane: waitingPane)],
            activeTabID: nil
        )

        #expect(state == .needsInput)
    }

    @Test("returns nil for terminal-only workspace")
    func terminalOnly() {
        let tab = TerminalTab(pane: TerminalPaneState(projectPath: "/tmp/wt"))

        let state = SidebarAgentActivityResolver.activityState(
            tabs: [tab],
            activeTabID: tab.id
        )

        #expect(state == nil)
    }
}
