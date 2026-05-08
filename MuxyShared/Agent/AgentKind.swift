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

public extension AgentKind {
    var defaultResumeRegex: String? {
        switch self {
        case .claudeCode:
            return #"(?m)^\s*claude\s+--resume\s+\S+.*$"#
        case .codex:
            return #"(?m)^\s*codex\s+resume\s+\S+.*$"#
        case .geminiCli, .openCode, .terminal:
            return nil
        }
    }

    var expectedBinaryName: String? {
        switch self {
        case .claudeCode: return "claude"
        case .codex:      return "codex"
        case .geminiCli:  return "gemini"
        case .openCode:   return "opencode"
        case .terminal:   return nil
        }
    }
}
