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

    @Test("summary preserves dominant state and agent counts")
    func summaryCountsAgentsByState() {
        let runningPane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .codex)
        runningPane.activityState = .running
        let waitingPane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .claudeCode)
        waitingPane.activityState = .needsInput
        let idlePane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .geminiCli)
        idlePane.activityState = .idle

        let summary = SidebarAgentActivityResolver.summary(
            tabs: [
                TerminalTab(pane: runningPane),
                TerminalTab(pane: waitingPane),
                TerminalTab(pane: idlePane),
            ],
            activeTabID: nil
        )

        #expect(summary?.dominantState == .needsInput)
        #expect(summary?.agentCount == 3)
        #expect(summary?.count(for: .needsInput) == 1)
        #expect(summary?.count(for: .running) == 1)
        #expect(summary?.count(for: .idle) == 1)
    }

    @Test("summary prioritizes waiting state while preserving all agent dots")
    func summaryPrioritizesWaitingStateAndAllAgentDots() {
        let runningPane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .codex)
        runningPane.activityState = .running
        let runningTab = TerminalTab(pane: runningPane)
        let waitingPane = TerminalPaneState(projectPath: "/tmp/wt", agentKind: .claudeCode)
        waitingPane.activityState = .needsInput

        let summary = SidebarAgentActivityResolver.summary(
            tabs: [
                runningTab,
                TerminalTab(pane: waitingPane),
            ],
            activeTabID: runningTab.id
        )

        #expect(summary?.dominantState == .needsInput)
        #expect(summary?.agentStates == [.running, .needsInput])
    }

    @Test("summary dot identities include state")
    func summaryDotIdentitiesIncludeState() {
        let completed = SidebarAgentActivitySummary(
            dominantState: .completed,
            agentStates: [.completed, .completed]
        )
        let idle = SidebarAgentActivitySummary(
            dominantState: .idle,
            agentStates: [.idle, .idle]
        )

        #expect(completed.dots.map(\.id) != idle.dots.map(\.id))
        #expect(completed.dots.map(\.state) == [.completed, .completed])
        #expect(idle.dots.map(\.state) == [.idle, .idle])
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

    @Test("summary returns nil for terminal-only workspace")
    func terminalOnlySummary() {
        let tab = TerminalTab(pane: TerminalPaneState(projectPath: "/tmp/wt"))

        let summary = SidebarAgentActivityResolver.summary(
            tabs: [tab],
            activeTabID: tab.id
        )

        #expect(summary == nil)
    }
}
