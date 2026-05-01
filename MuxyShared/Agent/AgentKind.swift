import Foundation

public enum AgentKind: String, Sendable, Codable, Hashable, CaseIterable {
    case terminal
    case claudeCode
    case codex
    case geminiCli
    case openCode

    public var displayName: String {
        switch self {
        case .terminal: "Terminal"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .geminiCli: "Gemini CLI"
        case .openCode: "OpenCode"
        }
    }

    public var iconSystemName: String {
        switch self {
        case .terminal: "terminal"
        case .claudeCode: "sparkles"
        case .codex: "brain"
        case .geminiCli: "star.circle"
        case .openCode: "hammer"
        }
    }

    public var providerIconName: String? {
        switch self {
        case .terminal: nil
        case .claudeCode: "claude"
        case .codex: "codex"
        case .geminiCli: "gemini"
        case .openCode: "opencode"
        }
    }
}
