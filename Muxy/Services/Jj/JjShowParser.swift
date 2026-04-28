import Foundation
import MuxyShared

enum JjShowParseError: Error, Sendable {
    case missingChange
    case malformed(String)
}

enum JjShowParser {
    static let template = [
        #""CHANGE\t" ++ self.change_id().shortest() ++ "\t" ++ self.change_id() ++ "\n""#,
        #"self.parents().map(|p| "PARENTS\t" ++ p.change_id().shortest() ++ "\t" ++ p.change_id()).join("\n")"#,
        #""\nDESCRIPTION\n" ++ self.description() ++ "END_DESCRIPTION\n""#,
    ].joined(separator: " ++ ")

    static func parse(_ raw: String) throws -> JjShowOutput {
        var change: JjChangeId?
        var parents: [JjChangeId] = []
        var descriptionLines: [String] = []
        var statLines: [String] = []
        var section: Section = .header

        for line in raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            switch section {
            case .header:
                if line.hasPrefix("CHANGE\t") {
                    change = try parseTaggedId(line, expectedTag: "CHANGE")
                } else if line.hasPrefix("PARENTS\t") {
                    parents.append(try parseTaggedId(line, expectedTag: "PARENTS"))
                } else if line == "DESCRIPTION" {
                    section = .description
                }
            case .description:
                if line == "END_DESCRIPTION" {
                    section = .stat
                } else {
                    descriptionLines.append(line)
                }
            case .stat:
                if !line.isEmpty { statLines.append(line) }
            }
        }

        guard let change else { throw JjShowParseError.missingChange }
        let description = descriptionLines.joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        let diffStat = statLines.isEmpty ? nil : try JjDiffParser.parseStat(statLines.joined(separator: "\n"))
        return JjShowOutput(change: change, parents: parents, description: description, diffStat: diffStat)
    }

    private static func parseTaggedId(_ line: String, expectedTag: String) throws -> JjChangeId {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == expectedTag else {
            throw JjShowParseError.malformed(line)
        }
        let shortToken = String(parts[1])
        let fullToken = String(parts[2])
        return JjChangeId(prefix: shortToken, full: fullToken.isEmpty ? shortToken : fullToken)
    }

    private enum Section {
        case header
        case description
        case stat
    }
}
