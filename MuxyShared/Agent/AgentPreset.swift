import Foundation

public struct AgentPreset: Sendable, Hashable {
    public let kind: AgentKind
    public let defaultCommand: String?
    public let env: [String: String]
    public let requiresDedicatedWorkspace: Bool

    public init(
        kind: AgentKind,
        defaultCommand: String?,
        env: [String: String] = [:],
        requiresDedicatedWorkspace: Bool = false
    ) {
        self.kind = kind
        self.defaultCommand = defaultCommand
        self.env = env
        self.requiresDedicatedWorkspace = requiresDedicatedWorkspace
    }
}

public enum AgentPresetCatalog {
    public static func preset(for kind: AgentKind) -> AgentPreset {
        builtIn(for: kind)
    }

    public static func preset(
        for kind: AgentKind,
        env: [String: String] = [:],
        configuredPresets: [RoostConfigAgentPreset]
    ) -> AgentPreset {
        if let override = configuredPresets.first(where: { $0.kind == kind }) {
            return AgentPreset(
                kind: kind,
                defaultCommand: override.command,
                env: env.merging(override.env) { _, override in override },
                requiresDedicatedWorkspace: override.cardinality == .dedicated
            )
        }
        let preset = builtIn(for: kind)
        return AgentPreset(
            kind: preset.kind,
            defaultCommand: preset.defaultCommand,
            env: preset.env.merging(env) { _, override in override },
            requiresDedicatedWorkspace: preset.requiresDedicatedWorkspace
        )
    }

    private static func builtIn(for kind: AgentKind) -> AgentPreset {
        switch kind {
        case .terminal:
            AgentPreset(kind: .terminal, defaultCommand: nil)
        case .claudeCode:
            AgentPreset(kind: .claudeCode, defaultCommand: "claude --dangerously-skip-permissions")
        case .codex:
            AgentPreset(kind: .codex, defaultCommand: "codex --dangerously-bypass-approvals-and-sandbox")
        case .geminiCli:
            AgentPreset(kind: .geminiCli, defaultCommand: "gemini --yolo")
        case .openCode:
            AgentPreset(
                kind: .openCode,
                defaultCommand: "opencode",
                env: ["OPENCODE_PERMISSION": "{\"*\":\"allow\"}"]
            )
        }
    }
}
