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
        #""\t" ++ self.description().first_line() ++ "\n\n""#,
    ].joined(separator: " ++ ")

    static func parse(_ raw: String) throws -> [JjLogEntry] {
        var entries: [JjLogEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.contains("\t") {
                entries.append(try parseLine(line))
            } else if isGraphOnlyLine(line) {
                appendGraphLine(line, to: &entries)
            } else {
                throw JjLogParseError.malformedLine(line)
            }
        }
        return entries
    }

    static func parseLenient(_ raw: String) -> [JjLogEntry] {
        var entries: [JjLogEntry] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
            if line.contains("\t"), let entry = try? parseLine(line) {
                entries.append(entry)
            } else if isGraphOnlyLine(line) {
                appendGraphLine(line, to: &entries)
            }
        }
        return entries
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

    private static func appendGraphLine(_ line: String, to entries: inout [JjLogEntry]) {
        guard let last = entries.popLast() else { return }
        entries.append(JjLogEntry(
            graphPrefix: last.graphPrefix,
            change: last.change,
            commitId: last.commitId,
            isEmpty: last.isEmpty,
            authorName: last.authorName,
            authorTimestamp: last.authorTimestamp,
            description: last.description,
            graphLinesAfter: last.graphLinesAfter + [line]
        ))
    }

    private static func isGraphOnlyLine(_ line: String) -> Bool {
        !line.isEmpty && line.allSatisfy { char in
            char.isWhitespace || "│─╭╮╰╯├┤┬┴┼╲╱╳~".contains(char)
        }
    }
}
