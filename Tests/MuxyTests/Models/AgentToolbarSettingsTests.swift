import MuxyShared
import Testing

@testable import Roost

@Suite("AgentToolbarSettings")
struct AgentToolbarSettingsTests {
    @Test("defaults show every non-terminal agent")
    func defaultVisibleAgents() {
        let kinds = AgentToolbarSettings.visibleAgentKinds(from: AgentToolbarSettings.defaultVisibleAgentsRaw)

        #expect(kinds == [.claudeCode, .codex, .geminiCli, .openCode])
    }

    @Test("hidden agents stay hidden and keep catalog order")
    func hiddenAgents() {
        let raw = AgentToolbarSettings.setVisible(
            false,
            for: .codex,
            in: AgentToolbarSettings.defaultVisibleAgentsRaw
        )

        #expect(AgentToolbarSettings.visibleAgentKinds(from: raw) == [.claudeCode, .geminiCli, .openCode])

        let restored = AgentToolbarSettings.setVisible(true, for: .codex, in: raw)
        #expect(AgentToolbarSettings.visibleAgentKinds(from: restored) == [.claudeCode, .codex, .geminiCli, .openCode])
    }
}
