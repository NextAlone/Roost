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
        #expect(AgentPresetCatalog.preset(for: .claudeCode).defaultCommand == "claude --dangerously-skip-permissions")
        #expect(
            AgentPresetCatalog.preset(for: .codex).defaultCommand ==
                "codex --dangerously-bypass-approvals-and-sandbox"
        )
        #expect(AgentPresetCatalog.preset(for: .geminiCli).defaultCommand == "gemini --yolo")
        #expect(AgentPresetCatalog.preset(for: .openCode).defaultCommand == "opencode")
        #expect(AgentPresetCatalog.preset(for: .openCode).env == ["OPENCODE_PERMISSION": "{\"*\":\"allow\"}"])
    }

    @Test("requiresDedicatedWorkspace defaults to false for all built-ins")
    func dedicatedDefaultsFalse() {
        for kind in AgentKind.allCases {
            #expect(AgentPresetCatalog.preset(for: kind).requiresDedicatedWorkspace == false)
        }
    }

    @Test("configured override wins for a known kind")
    func overrideWinsForKind() {
        let configured = [RoostConfigAgentPreset(
            name: "Custom Claude",
            kind: .claudeCode,
            command: "claude --model opus",
            env: ["CLAUDE_CONFIG_DIR": ".roost/claude"],
            cardinality: .dedicated
        )]
        let preset = AgentPresetCatalog.preset(
            for: .claudeCode,
            env: ["GLOBAL": "1", "CLAUDE_CONFIG_DIR": "global"],
            configuredPresets: configured
        )
        #expect(preset.defaultCommand == "claude --model opus")
        #expect(preset.env == ["GLOBAL": "1", "CLAUDE_CONFIG_DIR": ".roost/claude"])
        #expect(preset.requiresDedicatedWorkspace == true)
    }

    @Test("kinds without override fall back to built-in")
    func unrelatedKindUsesBuiltIn() {
        let configured = [RoostConfigAgentPreset(
            name: "Custom Claude",
            kind: .claudeCode,
            command: "claude --model opus",
            cardinality: .dedicated
        )]
        let preset = AgentPresetCatalog.preset(for: .codex, configuredPresets: configured)
        #expect(preset.defaultCommand == "codex --dangerously-bypass-approvals-and-sandbox")
        #expect(preset.requiresDedicatedWorkspace == false)
    }
}
