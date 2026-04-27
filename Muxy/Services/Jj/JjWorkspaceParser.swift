import Foundation
import MuxyShared

enum JjWorkspaceParseError: Error, Sendable {
    case malformedLine(String)
}

enum JjWorkspaceParser {
    static func parse(_ raw: String) throws -> [JjWorkspaceEntry] {
        var entries: [JjWorkspaceEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line)
            guard let colon = s.firstIndex(of: ":") else {
                throw JjWorkspaceParseError.malformedLine(s)
            }
            let name = String(s[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = s[s.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let firstSpace = rest.firstIndex(of: " ") ?? rest.endIndex
            let id = String(rest[..<firstSpace])
            entries.append(JjWorkspaceEntry(
                name: name,
                workingCopy: JjChangeId(prefix: id, full: id)
            ))
        }
        return entries
    }
}
