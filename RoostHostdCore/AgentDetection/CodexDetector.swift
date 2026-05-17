import Foundation

public struct CodexDetector: AgentDetector {
    public let agentLabel = "codex"

    public init() {}

    public func detect(screenContent: String) -> AgentDetectionState {
        let lower = screenContent.lowercased()

        if lower.contains("press enter to confirm or esc to cancel")
            || lower.contains("enter to submit answer")
            || lower.contains("allow command?")
            || lower.contains("[y/n]")
            || lower.contains("yes (y)")
        {
            return .blocked
        }
        if hasConfirmationPrompt(lower) {
            return .blocked
        }

        if hasInterruptPattern(lower) || hasWorkingHeader(screenContent) {
            return .working
        }

        return .idle
    }

    private func hasConfirmationPrompt(_ lower: String) -> Bool {
        guard let pos = lower.range(of: "do you want")?.lowerBound
            ?? lower.range(of: "would you like")?.lowerBound
        else {
            return false
        }
        return lower[pos...].contains("yes") || lower[pos...].contains("\u{276F}")
    }

    private func hasInterruptPattern(_ lower: String) -> Bool {
        lower.contains("esc to interrupt")
            || lower.contains("ctrl+c to interrupt")
            || (lower.contains("esc") && lower.contains("interrupt"))
    }

    private func hasWorkingHeader(_ content: String) -> Bool {
        content.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("\u{2022}") && trimmed.contains("Working (")
        }
    }
}
