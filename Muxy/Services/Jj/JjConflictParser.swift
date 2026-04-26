import Foundation
import MuxyShared

public enum JjConflictParser {
    public static func parse(_ raw: String) -> [JjConflict] {
        raw.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            if let firstWS = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) {
                return JjConflict(path: String(trimmed[..<firstWS]))
            }
            return JjConflict(path: trimmed)
        }
    }
}
