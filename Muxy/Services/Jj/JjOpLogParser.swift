import Foundation
import MuxyShared

public enum JjOpLogParseError: Error, Sendable {
    case malformedLine(String)
}

public enum JjOpLogParser {
    public static let template = #"self.id().short() ++ "\t" ++ self.time().end().format("%Y-%m-%dT%H:%M:%S%:z") ++ "\t" ++ self.description() ++ "\n""#

    public static func parse(_ raw: String) throws -> [JjOperation] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        var ops: [JjOperation] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else {
                throw JjOpLogParseError.malformedLine(String(line))
            }
            guard let date = formatter.date(from: String(parts[1])) else {
                throw JjOpLogParseError.malformedLine(String(line))
            }
            ops.append(JjOperation(
                id: String(parts[0]),
                timestamp: date,
                description: String(parts[2])
            ))
        }
        return ops
    }
}
