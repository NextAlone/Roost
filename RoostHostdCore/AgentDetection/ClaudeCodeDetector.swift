import Foundation

public struct ClaudeCodeDetector: AgentDetector {
    public let agentLabel = "claude"

    public init() {}

    public func detectEvidence(screenContent: String) -> AgentScreenEvidence {
        let lower = screenContent.lowercased()

        if screenContent.contains("\u{2315} Search") {
            return AgentScreenEvidence(state: .idle, signal: .idlePrompt)
        }
        if lower.contains("ctrl+r to toggle") {
            return AgentScreenEvidence(state: .idle, signal: .idlePrompt)
        }
        if lower.contains("interrupted") && lower.contains("what should claude do instead") {
            return AgentScreenEvidence(state: .idle, signal: .interruptedPrompt)
        }

        if hasBlockedPrompt(screenContent, lower) {
            return AgentScreenEvidence(state: .blocked, signal: .blockedPrompt)
        }

        let above = contentAbovePromptBox(screenContent)
        let aboveLower = above.lowercased()

        if aboveLower.contains("esc to interrupt") || aboveLower.contains("ctrl+c to interrupt") {
            return AgentScreenEvidence(state: .working, signal: .workingIndicator)
        }

        if hasActiveStatusIndicator(above) {
            return AgentScreenEvidence(state: .working, signal: .workingIndicator)
        }

        if hasCompletionLineInRecentLines(above) {
            return AgentScreenEvidence(state: .idle, signal: .completionLine)
        }

        if hasSpinnerInRecentLines(above) {
            return AgentScreenEvidence(state: .working, signal: .workingIndicator)
        }

        return AgentScreenEvidence(state: .idle, signal: .idlePrompt)
    }

    private func hasActiveStatusIndicator(_ aboveContent: String) -> Bool {
        for line in aboveContent.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if isFinishedStatusLine(trimmed) { return false }
            if trimmed.range(of: #"\b\p{L}*ing\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
                return true
            }
        }
        return false
    }

    private func hasCompletionLineInRecentLines(_ aboveContent: String) -> Bool {
        var emptyGap = 0
        for line in aboveContent.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                emptyGap += 1
                continue
            }
            if emptyGap > 5 { return false }
            emptyGap = 0
            if isFinishedStatusLine(trimmed) {
                return true
            }
        }
        return false
    }

    private func hasSpinnerInRecentLines(_ aboveContent: String) -> Bool {
        let spinnerChars =
            Set(
                "\u{00B7}\u{2731}\u{2732}\u{2733}\u{2734}\u{2735}\u{2736}\u{2737}\u{2738}\u{2739}\u{273A}\u{273B}\u{273C}\u{273D}\u{273E}\u{273F}\u{2740}\u{2741}\u{2742}\u{2743}\u{2747}\u{2748}\u{2749}\u{274A}\u{274B}\u{2722}\u{2723}\u{2724}\u{2725}\u{2726}\u{2727}\u{2728}\u{229B}\u{2295}\u{2299}\u{25C9}\u{25CE}\u{2042}\u{2055}\u{203B}\u{235F}\u{2606}\u{2605}"
            )
        var emptyGap = 0
        for line in aboveContent.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                emptyGap += 1
                continue
            }
            if emptyGap > 5 { return false }
            emptyGap = 0
            if isFinishedStatusLine(trimmed) {
                return false
            }
            if let first = trimmed.first, spinnerChars.contains(first) {
                return true
            }
        }
        return false
    }

    private func isFinishedStatusLine(_ line: String) -> Bool {
        line.range(of: #"^\S+\s+\S+(?:ed|lt|nt|pt|ught)\s+for\s+\d+(?:\.\d+)?\s*(?:ms|s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func hasBlockedPrompt(_ content: String, _ lower: String) -> Bool {
        if lower.contains("do you want to proceed?")
            || lower.contains("would you like to proceed?")
            || lower.contains("waiting for permission")
            || lower.contains("do you want to allow this connection?")
            || lower.contains("tab to amend")
            || lower.contains("ctrl+e to explain")
            || lower.contains("chat about this")
            || lower.contains("review your answers")
            || lower.contains("skip interview and plan immediately")
        {
            return true
        }
        if hasConfirmationPrompt(lower) {
            return true
        }
        if hasSelectionPrompt(content) && hasYesNoChoice(content) {
            return true
        }
        return false
    }

    private func hasConfirmationPrompt(_ lower: String) -> Bool {
        guard let pos = lower.range(of: "do you want")?.lowerBound
            ?? lower.range(of: "would you like")?.lowerBound
        else {
            return false
        }
        let after = lower[pos...]
        return after.contains("yes") || after.contains("\u{276F}")
    }

    private func hasSelectionPrompt(_ content: String) -> Bool {
        for line in content.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\u{276F}"),
               trimmed.contains(where: { $0.isNumber }),
               trimmed.contains(".")
            {
                return true
            }
        }
        return false
    }

    private func hasYesNoChoice(_ content: String) -> Bool {
        content.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\u{276F}"))
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            return trimmed == "yes" || trimmed == "no"
                || trimmed.hasPrefix("1. yes") || trimmed.hasPrefix("2. no")
                || trimmed.hasPrefix("yes, and ") || trimmed.hasPrefix("no, and tell claude")
        }
    }

    private func contentAbovePromptBox(_ content: String) -> String {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var borderCount = 0
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty, trimmed.allSatisfy({ $0 == "\u{2500}" }) {
                borderCount += 1
                if borderCount == 2 {
                    return lines[0 ..< i].joined(separator: "\n")
                }
            }
        }
        return content
    }
}
