import Foundation
import MuxyShared

enum JjConflictParser {
    static func parse(_ raw: String) -> [JjConflict] {
        raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let s = String(line)
            let columnSeparator = s.range(of: #"(\t|  +)"#, options: .regularExpression)
            let pathSlice: Substring = if let columnSeparator {
                s[..<columnSeparator.lowerBound]
            } else {
                Substring(s)
            }
            let path = String(pathSlice).trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { return nil }
            return JjConflict(path: path)
        }
    }
}
