import Foundation

public struct AgentPreset: Sendable, Hashable {
    public let kind: AgentKind
    public let defaultCommand: String?
    public let requiresDedicatedWorkspace: Bool

    public init(kind: AgentKind, defaultCommand: String?, requiresDedicatedWorkspace: Bool = false) {
        self.kind = kind
        self.defaultCommand = defaultCommand
        self.requiresDedicatedWorkspace = requiresDedicatedWorkspace
    }
}

public enum AgentPresetCatalog {
    public static func preset(for kind: AgentKind) -> AgentPreset {
        switch kind {
        case .terminal:
            AgentPreset(kind: .terminal, defaultCommand: nil)
        case .claudeCode:
            AgentPreset(kind: .claudeCode, defaultCommand: "claude")
        case .codex:
            AgentPreset(kind: .codex, defaultCommand: "codex")
        case .geminiCli:
            AgentPreset(kind: .geminiCli, defaultCommand: "gemini")
        case .openCode:
            AgentPreset(kind: .openCode, defaultCommand: "opencode")
        }
    }
}
