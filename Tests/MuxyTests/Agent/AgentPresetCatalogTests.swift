import Foundation
import MuxyShared
import Testing

@Suite("AgentPresetCatalog resume regex")
struct AgentPresetCatalogResumeTests {
    @Test("built-in presets have nil resumeCommandRegex override")
    func builtInPresetsHaveNilOverride() {
        #expect(AgentPresetCatalog.preset(for: .claudeCode).resumeCommandRegex == nil)
        #expect(AgentPresetCatalog.preset(for: .codex).resumeCommandRegex == nil)
    }

    @Test("configured override threads resumeCommandRegex through")
    func configuredOverrideThreadsThrough() {
        let configured = [
            RoostConfigAgentPreset(
                name: "X",
                kind: .claudeCode,
                command: "claude --foo",
                resumeCommandRegex: "(?m)^claude --continue$"
            )
        ]
        let preset = AgentPresetCatalog.preset(
            for: .claudeCode,
            env: [:],
            configuredPresets: configured
        )
        #expect(preset.resumeCommandRegex == "(?m)^claude --continue$")
        #expect(preset.defaultCommand == "claude --foo")
    }
}
