import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("Agent tab creation")
struct AgentTabCreationTests {
    @Test("createAgentTab(.terminal) is identical to createTab")
    func terminalCase() {
        let area = TabArea(projectPath: "/tmp/wt")
        let countBefore = area.tabs.count
        area.createAgentTab(kind: .terminal)
        #expect(area.tabs.count == countBefore + 1)
        let pane = area.activeTab?.content.pane
        #expect(pane?.agentKind == .terminal)
        #expect(pane?.startupCommand == nil)
    }

    @Test("createAgentTab(.claudeCode) sets agentKind + preset command")
    func claudeCase() {
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        let pane = area.activeTab?.content.pane
        #expect(pane?.agentKind == .claudeCode)
        #expect(pane?.startupCommand == "claude")
        #expect(pane?.projectPath == "/tmp/wt")
    }

    @Test("createAgentTab(.codex) cwd is the TabArea projectPath (active worktree)")
    func cwdEqualsWorktreePath() {
        let area = TabArea(projectPath: "/Users/me/repo/wt-feature-x")
        area.createAgentTab(kind: .codex)
        let pane = area.activeTab?.content.pane
        #expect(pane?.projectPath == "/Users/me/repo/wt-feature-x")
        #expect(pane?.startupCommand == "codex")
    }
}
