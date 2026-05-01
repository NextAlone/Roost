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
        #expect(pane?.activityState == .idle)
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

    @Test("Claude Code tab default title shows agent name")
    func claudeTabTitle() {
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        #expect(area.activeTab?.title == "Claude Code")
    }

    @Test("configured agent env is applied to pane")
    func configuredEnv() throws {
        let project = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-agent-env-tests")
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: project) }
        let roostDir = project.appendingPathComponent(".roost")
        try FileManager.default.createDirectory(at: roostDir, withIntermediateDirectories: true)
        try Data("""
        {
          "schemaVersion": 1,
          "env": { "GLOBAL": "1", "CLAUDE_CONFIG_DIR": "global" },
          "agentPresets": [
            {
              "name": "Claude",
              "kind": "claudeCode",
              "command": "claude",
              "env": { "CLAUDE_CONFIG_DIR": ".roost/claude" }
            }
          ]
        }
        """.utf8).write(to: roostDir.appendingPathComponent("config.json"))

        let area = TabArea(projectPath: project.path)
        area.createAgentTab(kind: .claudeCode)
        #expect(area.activeTab?.content.pane?.env == ["GLOBAL": "1", "CLAUDE_CONFIG_DIR": ".roost/claude"])
    }

    @Test("custom title overrides agent display name")
    func customTitleWins() {
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let tab = area.activeTab
        tab?.customTitle = "Codex (debug)"
        #expect(tab?.title == "Codex (debug)")
    }
}
