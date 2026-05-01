import Foundation
import MuxyShared

enum JjLogParseError: Error, Sendable {
    case malformedLine(String)
}

enum JjLogParser {
    static let template = [
        #"self.change_id().shortest()"#,
        #""\t" ++ self.commit_id().short()"#,
        #""\t" ++ if(self.empty(), "empty", "nonempty")"#,
        #""\t" ++ self.author().name()"#,
        #""\t" ++ self.author().timestamp().format("%Y-%m-%dT%H:%M:%S%:z")"#,
        #""\t" ++ self.description().first_line() ++ "\n""#,
    ].joined(separator: " ++ ")

    static func parse(_ raw: String) throws -> [JjLogEntry] {
        try raw.split(separator: "\n", omittingEmptySubsequences: true).map { line in
            try parseLine(String(line))
        }
    }

    static func parseLenient(_ raw: String) -> [JjLogEntry] {
        raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            try? parseLine(String(line))
        }
    }

    static func parseLine(_ line: String) throws -> JjLogEntry {
        let parts = line.split(separator: "\t", maxSplits: 5, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else {
            throw JjLogParseError.malformedLine(line)
        }
        let prefixAndChange = parseGraphPrefixAndChange(parts[0])
        guard !prefixAndChange.changePrefix.isEmpty else {
            throw JjLogParseError.malformedLine(line)
        }
        return JjLogEntry(
            graphPrefix: prefixAndChange.graphPrefix,
            change: JjChangeId(prefix: prefixAndChange.changePrefix, full: prefixAndChange.changePrefix),
            commitId: parts[1],
            isEmpty: parts[2] == "empty",
            authorName: parts[3],
            authorTimestamp: parts[4],
            description: parts.count > 5 ? parts[5] : ""
        )
    }

    private static func parseGraphPrefixAndChange(_ raw: String) -> (graphPrefix: String, changePrefix: String) {
        let end = raw.endIndex
        var tokenEnd = end
        while tokenEnd > raw.startIndex, raw[raw.index(before: tokenEnd)].isWhitespace {
            tokenEnd = raw.index(before: tokenEnd)
        }
        var tokenStart = tokenEnd
        while tokenStart > raw.startIndex, !raw[raw.index(before: tokenStart)].isWhitespace {
            tokenStart = raw.index(before: tokenStart)
        }
        return (
            graphPrefix: String(raw[..<tokenStart]),
            changePrefix: String(raw[tokenStart ..< tokenEnd])
        )
    }
}
