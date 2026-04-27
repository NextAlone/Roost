import Foundation
import MuxyShared

enum JjDiffParseError: Error, Sendable {
    case malformedFileLine(String)
}

enum JjDiffParser {
    static func parseStat(_ raw: String) throws -> JjDiffStat {
        var files: [JjDiffFileStat] = []
        var totalAdditions = 0
        var totalDeletions = 0

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let s = String(line)
            if let summary = parseSummaryLine(s) {
                totalAdditions = summary.additions
                totalDeletions = summary.deletions
                continue
            }
            files.append(try parseFileLine(s))
        }
        return JjDiffStat(files: files, totalAdditions: totalAdditions, totalDeletions: totalDeletions)
    }

    private static func parseFileLine(_ s: String) throws -> JjDiffFileStat {
        guard let pipe = s.firstIndex(of: "|") else {
            throw JjDiffParseError.malformedFileLine(s)
        }
        let path = String(s[..<pipe]).trimmingCharacters(in: .whitespaces)
        let counts = String(s[s.index(after: pipe)...]).trimmingCharacters(in: .whitespaces)
        let parts = counts.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw JjDiffParseError.malformedFileLine(s)
        }
        let symbols = String(parts[1])
        let additions = symbols.filter { $0 == "+" }.count
        let deletions = symbols.filter { $0 == "-" }.count
        return JjDiffFileStat(path: path, additions: additions, deletions: deletions)
    }

    private struct Summary {
        let additions: Int
        let deletions: Int
    }

    private static func parseSummaryLine(_ s: String) -> Summary? {
        guard s.contains("file") && s.contains("changed") else { return nil }
        let additions = extract(numberBefore: "insertion", in: s) ?? 0
        let deletions = extract(numberBefore: "deletion", in: s) ?? 0
        return Summary(additions: additions, deletions: deletions)
    }

    private static func extract(numberBefore keyword: String, in s: String) -> Int? {
        guard let range = s.range(of: keyword) else { return nil }
        let before = s[..<range.lowerBound]
        let trimmed = before.trimmingCharacters(in: .whitespaces)
        let lastToken = trimmed.split(separator: " ").last.map(String.init) ?? ""
        return Int(lastToken)
    }
}
