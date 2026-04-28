import Foundation
import MuxyShared

enum JjBookmarkParseError: Error, Sendable {
    case malformedLine(String)
}

enum JjBookmarkParser {
    static let template = [
        #"self.name() ++ "\t" ++ self.remote() ++ "\t""#,
        #"if(self.normal_target(), self.normal_target().change_id().shortest(), "") ++ "\t""#,
        #"if(self.normal_target(), self.normal_target().change_id(), "") ++ "\n""#,
    ].joined(separator: " ++ ")

    static func parse(_ raw: String) throws -> [JjBookmark] {
        var byName: [String: JjBookmark] = [:]
        var order: [String] = []

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
            guard parts.count == 4 else {
                throw JjBookmarkParseError.malformedLine(String(line))
            }
            let name = String(parts[0])
            let remote = String(parts[1])
            let shortPrefix = String(parts[2])
            let fullId = String(parts[3])

            let target: JjChangeId? = if shortPrefix.isEmpty {
                nil
            } else {
                JjChangeId(prefix: shortPrefix, full: fullId.isEmpty ? shortPrefix : fullId)
            }

            if byName[name] == nil {
                order.append(name)
                byName[name] = JjBookmark(name: name, target: target, isLocal: false, remotes: [])
            }
            guard var existing = byName[name] else { continue }

            if remote.isEmpty {
                existing = JjBookmark(
                    name: name,
                    target: target,
                    isLocal: true,
                    remotes: existing.remotes
                )
            } else {
                let resolvedTarget = existing.target ?? target
                var remotes = existing.remotes
                remotes.append(remote)
                existing = JjBookmark(
                    name: name,
                    target: resolvedTarget,
                    isLocal: existing.isLocal,
                    remotes: remotes
                )
            }
            byName[name] = existing
        }
        return order.compactMap { byName[$0] }
    }
}
