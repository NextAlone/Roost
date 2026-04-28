import Foundation
import MuxyShared

enum JjStatusParseError: Error, Sendable {
    case missingWorkingCopy
    case malformedChangeId(String)
}

enum JjStatusParser {
    static let workingCopyLabel = "Working copy  (@) : "
    static let parentCommitLabel = "Parent commit (@-): "
    static let cleanMessage = "The working copy has no changes."
    static let conflictHeaderPrefix = "There are unresolved conflicts"

    static func parse(_ raw: String) throws -> JjStatus {
        var entries: [JjStatusEntry] = []
        var workingCopy: JjChangeId?
        var parent: JjChangeId?
        var workingCopySummary = ""
        var hasConflicts = false
        var inConflictBlock = false

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("Working copy changes:") || s == cleanMessage {
                inConflictBlock = false
                continue
            }
            if s.hasPrefix(conflictHeaderPrefix) {
                hasConflicts = true
                inConflictBlock = true
                continue
            }
            if let parsed = try parseLabeledLine(s, label: workingCopyLabel) {
                workingCopy = parsed.changeId
                workingCopySummary = parsed.trailingDescription
                inConflictBlock = false
                continue
            }
            if let parsed = try parseLabeledLine(s, label: parentCommitLabel) {
                parent = parsed.changeId
                inConflictBlock = false
                continue
            }
            if inConflictBlock {
                continue
            }
            if let entry = parseChangeLine(s) {
                entries.append(entry)
            }
        }

        guard let workingCopy else {
            throw JjStatusParseError.missingWorkingCopy
        }
        return JjStatus(
            workingCopy: workingCopy,
            parent: parent,
            workingCopySummary: workingCopySummary,
            entries: entries,
            hasConflicts: hasConflicts
        )
    }

    static func parseSummaryEntries(_ raw: String) throws -> [JjStatusEntry] {
        var entries: [JjStatusEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            if let entry = parseChangeLine(String(line)) {
                entries.append(entry)
            }
        }
        return entries
    }

    private static func parseLabeledLine(_ s: String, label: String) throws -> ChangeLinePrefix? {
        guard s.hasPrefix(label) else { return nil }
        let rest = String(s.dropFirst(label.count))
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let token = parts.first else {
            throw JjStatusParseError.malformedChangeId(s)
        }
        let changeId = try parseChangeId(String(token))
        let trailing = parts.count > 1 ? String(parts[1]) : ""
        return ChangeLinePrefix(changeId: changeId, trailingDescription: trailing)
    }

    static func parseChangeId(_ token: String) throws -> JjChangeId {
        guard let openBracket = token.firstIndex(of: "[") else {
            return JjChangeId(prefix: token, full: token)
        }
        guard token.last == "]" else {
            throw JjStatusParseError.malformedChangeId(token)
        }
        let prefix = String(token[..<openBracket])
        let suffixStart = token.index(after: openBracket)
        let suffixEnd = token.index(before: token.endIndex)
        let suffix = String(token[suffixStart ..< suffixEnd])
        return JjChangeId(prefix: prefix, full: prefix + suffix)
    }

    private static func parseChangeLine(_ s: String) -> JjStatusEntry? {
        guard s.count > 2, s[s.index(s.startIndex, offsetBy: 1)] == " " else { return nil }
        guard let first = s.first else { return nil }
        let code = String(first)
        guard let change = JjFileChange(rawValue: code) else { return nil }
        let rest = String(s.dropFirst(2))
        if change == .renamed || change == .copied,
           let arrow = rest.range(of: " -> ")
        {
            return JjStatusEntry(
                change: change,
                path: String(rest[arrow.upperBound...]),
                oldPath: String(rest[..<arrow.lowerBound])
            )
        }
        return JjStatusEntry(change: change, path: rest)
    }
}

private struct ChangeLinePrefix {
    let changeId: JjChangeId
    let trailingDescription: String
}
