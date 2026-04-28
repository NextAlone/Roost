import Foundation
import MuxyShared

enum JjVersionParseError: Error, Sendable {
    case malformed(String)
}

extension JjVersion {
    static let minimumSupported = JjVersion(major: 0, minor: 20, patch: 0)

    static func parse(_ raw: String) throws -> JjVersion {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0] == "jj" else {
            throw JjVersionParseError.malformed(raw)
        }
        let versionToken = parts[1].split(separator: "-", maxSplits: 1).first ?? parts[1]
        let nums = versionToken.split(separator: ".")
        guard nums.count == 3,
              let major = Int(nums[0]),
              let minor = Int(nums[1]),
              let patch = Int(nums[2])
        else {
            throw JjVersionParseError.malformed(raw)
        }
        return JjVersion(major: major, minor: minor, patch: patch)
    }
}
