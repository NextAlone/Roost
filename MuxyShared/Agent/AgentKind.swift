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
        case .claudeCode: #"(?m)^\s*claude\s+--resume\s+\S+.*$"#
        case .codex: #"(?m)^\s*codex\s+resume\s+\S+.*$"#
        case .geminiCli, .openCode, .terminal: nil
        }
    }

    var expectedBinaryName: String? {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .geminiCli: "gemini"
        case .openCode: "opencode"
        case .terminal: nil
        }
    }
}
