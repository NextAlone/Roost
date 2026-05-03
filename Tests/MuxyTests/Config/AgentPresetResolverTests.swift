import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("AgentPresetResolver")
struct AgentPresetResolverTests {
    @Test("app-wide presets override built-ins and merge project env")
    func appPresetMergesProjectEnv() {
        let appConfig = RoostConfig(
            env: ["APP": "1", "SHARED": "app"],
            agentPresets: [
                RoostConfigAgentPreset(
                    name: "Codex",
                    kind: .codex,
                    command: "codex --profile roost",
                    env: ["PRESET": "1", "SHARED": "preset"],
                    cardinality: .dedicated
                )
            ]
        )
        let projectConfig = RoostConfig(env: ["PROJECT": "1", "SHARED": "project"])

        let preset = AgentPresetResolver.preset(
            for: .codex,
            appConfig: appConfig,
            projectConfig: projectConfig
        )

        #expect(preset.defaultCommand == "codex --profile roost")
        #expect(preset.env == [
            "APP": "1",
            "PROJECT": "1",
            "PRESET": "1",
            "SHARED": "preset",
        ])
        #expect(preset.requiresDedicatedWorkspace)
    }

    @Test("project agentPresets are ignored")
    func projectPresetIgnored() {
        let projectConfig = RoostConfig(agentPresets: [
            RoostConfigAgentPreset(
                name: "Project Codex",
                kind: .codex,
                command: "codex --project",
                cardinality: .dedicated
            )
        ])

        let preset = AgentPresetResolver.preset(
            for: .codex,
            appConfig: nil,
            projectConfig: projectConfig
        )

        #expect(preset.defaultCommand == "codex --dangerously-bypass-approvals-and-sandbox")
        #expect(!preset.requiresDedicatedWorkspace)
    }

    @Test("built-in OpenCode yolo env is preserved")
    func openCodeBuiltinEnvPreserved() {
        let preset = AgentPresetResolver.preset(
            for: .openCode,
            appConfig: nil,
            projectConfig: nil
        )

        #expect(preset.defaultCommand == "opencode")
        #expect(preset.env == ["OPENCODE_PERMISSION": "{\"*\":\"allow\"}"])
    }
}
