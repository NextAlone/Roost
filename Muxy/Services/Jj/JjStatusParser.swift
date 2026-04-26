import Foundation
import MuxyShared

public enum JjStatusParseError: Error, Sendable {
    case missingWorkingCopy
}

public enum JjStatusParser {
    public static func parse(_ raw: String) throws -> JjStatus {
        var entries: [JjStatusEntry] = []
        var workingCopy: JjChangeId?
        var parent: JjChangeId?
        var description = ""
        var hasConflicts = false
        var inConflictBlock = false

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("Working copy changes:") || s == "The working copy is clean" {
                inConflictBlock = false
                continue
            }
            if s.hasPrefix("There are unresolved conflicts") {
                hasConflicts = true
                inConflictBlock = true
                continue
            }
            if let prefix = s.prefixIfWorkingCopyLine() {
                workingCopy = prefix.changeId
                description = prefix.trailingDescription
                inConflictBlock = false
                continue
            }
            if let prefix = s.prefixIfParentLine() {
                parent = prefix.changeId
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
            description: description,
            entries: entries,
            hasConflicts: hasConflicts
        )
    }

    private static func parseChangeLine(_ s: String) -> JjStatusEntry? {
        guard s.count > 2, s[s.index(s.startIndex, offsetBy: 1)] == " " else { return nil }
        let code = String(s.first!)
        guard let change = JjFileChange(rawValue: code) else { return nil }
        let rest = String(s.dropFirst(2))
        if change == .renamed || change == .copied,
           let arrow = rest.range(of: " -> ") {
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

private extension String {
    func prefixIfWorkingCopyLine() -> ChangeLinePrefix? {
        prefixIfMatchesLabel("Working copy : ")
    }

    func prefixIfParentLine() -> ChangeLinePrefix? {
        prefixIfMatchesLabel("Parent commit: ")
    }

    private func prefixIfMatchesLabel(_ label: String) -> ChangeLinePrefix? {
        guard hasPrefix(label) else { return nil }
        let rest = String(dropFirst(label.count))
        let parts = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first else { return nil }
        let id = JjChangeId(prefix: String(first), full: String(first))
        let trailing = parts.count > 1 ? String(parts[1]) : ""
        return ChangeLinePrefix(changeId: id, trailingDescription: trailing)
    }
}
