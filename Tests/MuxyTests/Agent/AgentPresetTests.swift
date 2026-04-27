import Foundation
import MuxyShared
import Testing

@Suite("AgentPreset")
struct AgentPresetTests {
    @Test("catalog has a preset for every AgentKind")
    func catalogCoversAllKinds() {
        for kind in AgentKind.allCases {
            #expect(AgentPresetCatalog.preset(for: kind).kind == kind)
        }
    }

    @Test("terminal preset has no startup command")
    func terminalIsBare() {
        let preset = AgentPresetCatalog.preset(for: .terminal)
        #expect(preset.defaultCommand == nil)
        #expect(preset.requiresDedicatedWorkspace == false)
    }

    @Test("command strings match expected CLI entry points")
    func commandValues() {
        #expect(AgentPresetCatalog.preset(for: .claudeCode).defaultCommand == "claude")
        #expect(AgentPresetCatalog.preset(for: .codex).defaultCommand == "codex")
        #expect(AgentPresetCatalog.preset(for: .geminiCli).defaultCommand == "gemini")
        #expect(AgentPresetCatalog.preset(for: .openCode).defaultCommand == "opencode")
    }

    @Test("requiresDedicatedWorkspace defaults to false for all built-ins")
    func dedicatedDefaultsFalse() {
        for kind in AgentKind.allCases {
            #expect(AgentPresetCatalog.preset(for: kind).requiresDedicatedWorkspace == false)
        }
    }
}
