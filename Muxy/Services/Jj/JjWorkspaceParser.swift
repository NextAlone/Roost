import Foundation
import MuxyShared

enum JjWorkspaceParseError: Error, Sendable {
    case malformedLine(String)
}

enum JjWorkspaceParser {
    static let template = #"self.name() ++ "\t" ++ self.target().change_id() ++ "\n""#

    static func parse(_ raw: String) throws -> [JjWorkspaceEntry] {
        var entries: [JjWorkspaceEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw JjWorkspaceParseError.malformedLine(String(line))
            }
            let name = String(parts[0])
            let fullId = String(parts[1])
            entries.append(JjWorkspaceEntry(
                name: name,
                workingCopy: JjChangeId(prefix: String(fullId.prefix(12)), full: fullId)
            ))
        }
        return entries
    }
}
