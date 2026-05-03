import Foundation
import MuxyShared

enum AgentPresetResolver {
    static func preset(for kind: AgentKind, appConfig: RoostConfig?, projectConfig: RoostConfig?) -> AgentPreset {
        let appEnv = RoostConfigEnvResolver.resolve(
            plain: appConfig?.env ?? [:],
            keychain: appConfig?.keychainEnv ?? [:]
        )
        let projectEnv = RoostConfigEnvResolver.resolve(
            plain: projectConfig?.env ?? [:],
            keychain: projectConfig?.keychainEnv ?? [:]
        )
        let env = appEnv.merging(projectEnv) { _, project in project }
        return AgentPresetCatalog.preset(
            for: kind,
            env: env,
            configuredPresets: resolvedPresets(appConfig?.agentPresets ?? [])
        )
    }

    private static func resolvedPresets(_ presets: [RoostConfigAgentPreset]) -> [RoostConfigAgentPreset] {
        presets.map { preset in
            RoostConfigAgentPreset(
                name: preset.name,
                kind: preset.kind,
                command: preset.command,
                env: RoostConfigEnvResolver.resolve(plain: preset.env, keychain: preset.keychainEnv),
                cardinality: preset.cardinality
            )
        }
    }
}
