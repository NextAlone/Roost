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
}
