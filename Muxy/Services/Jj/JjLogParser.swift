import Foundation
import MuxyShared

enum JjLogParseError: Error, Sendable {
    case malformedLine(String)
}

enum JjLogParser {
    private static let bookmarkLabelsTemplate = [
        #"self.bookmarks().map(|ref|"#,
        #"ref.name() ++ if(ref.conflict(), "??", "")"#,
        #"++ if(ref.remote(), "@" ++ ref.remote(), "")).join(" ")"#,
    ].joined(separator: " ")

    static let template = [
        #"self.change_id().shortest()"#,
        #""\t" ++ self.commit_id().short()"#,
        #""\t" ++ if(self.empty(), "empty", "nonempty")"#,
        #""\t" ++ if(self.immutable(), "immutable", "mutable")"#,
        #""\t" ++ self.author().name()"#,
        #""\t" ++ self.author().timestamp().format("%Y-%m-%dT%H:%M:%S%:z")"#,
        #""\t" ++ "# + bookmarkLabelsTemplate,
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
        let currentParts = line.split(separator: "\t", maxSplits: 7, omittingEmptySubsequences: false).map(String.init)
        if currentParts.count >= 8, isImmutableToken(currentParts[3]) {
            let prefixAndChange = parseGraphPrefixAndChange(currentParts[0])
            guard !prefixAndChange.changePrefix.isEmpty else {
                throw JjLogParseError.malformedLine(line)
            }
            return JjLogEntry(
                graphPrefix: prefixAndChange.graphPrefix,
                change: JjChangeId(prefix: prefixAndChange.changePrefix, full: prefixAndChange.changePrefix),
                commitId: currentParts[1],
                isEmpty: currentParts[2] == "empty",
                isImmutable: parseImmutableToken(currentParts[3]),
                authorName: currentParts[4],
                authorTimestamp: currentParts[5],
                bookmarkLabels: parseBookmarkLabels(currentParts[6]),
                description: currentParts[7]
            )
        }

        let parts = line.split(separator: "\t", maxSplits: 6, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 5 else {
            throw JjLogParseError.malformedLine(line)
        }
        let prefixAndChange = parseGraphPrefixAndChange(parts[0])
        guard !prefixAndChange.changePrefix.isEmpty else {
            throw JjLogParseError.malformedLine(line)
        }
        let bookmarkLabels: [String]
        let description: String
        if parts.count >= 7 {
            bookmarkLabels = parseBookmarkLabels(parts[5])
            description = parts[6]
        } else {
            bookmarkLabels = []
            description = parts.count > 5 ? parts[5] : ""
        }
        return JjLogEntry(
            graphPrefix: prefixAndChange.graphPrefix,
            change: JjChangeId(prefix: prefixAndChange.changePrefix, full: prefixAndChange.changePrefix),
            commitId: parts[1],
            isEmpty: parts[2] == "empty",
            authorName: parts[3],
            authorTimestamp: parts[4],
            bookmarkLabels: bookmarkLabels,
            description: description
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
            isImmutable: last.isImmutable,
            authorName: last.authorName,
            authorTimestamp: last.authorTimestamp,
            bookmarkLabels: last.bookmarkLabels,
            description: last.description,
            graphLinesAfter: last.graphLinesAfter + [line]
        ))
    }

    private static func parseBookmarkLabels(_ raw: String) -> [String] {
        raw.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    }

    private static func isImmutableToken(_ raw: String) -> Bool {
        raw == "immutable" || raw == "mutable" || raw == "true" || raw == "false"
    }

    private static func parseImmutableToken(_ raw: String) -> Bool {
        raw == "immutable" || raw == "true"
    }

    private static func isGraphOnlyLine(_ line: String) -> Bool {
        !line.isEmpty && line.allSatisfy { char in
            char.isWhitespace || "│─╭╮╰╯├┤┬┴┼╲╱╳~".contains(char)
        }
    }
}
