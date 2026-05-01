import Foundation

public struct JjChangeId: Hashable, Sendable, Codable {
    public let prefix: String
    public let full: String

    public init(prefix: String, full: String) {
        self.prefix = prefix
        self.full = full
    }
}

public struct JjBookmark: Hashable, Sendable, Codable {
    public let name: String
    public let target: JjChangeId?
    public let isLocal: Bool
    public let remotes: [String]

    public init(name: String, target: JjChangeId?, isLocal: Bool, remotes: [String]) {
        self.name = name
        self.target = target
        self.isLocal = isLocal
        self.remotes = remotes
    }
}

public struct JjLogEntry: Hashable, Sendable, Codable {
    public let graphPrefix: String
    public let change: JjChangeId
    public let commitId: String
    public let isEmpty: Bool
    public let isImmutable: Bool
    public let authorName: String
    public let authorTimestamp: String
    public let bookmarkLabels: [String]
    public let description: String
    public let graphLinesAfter: [String]

    public init(
        graphPrefix: String,
        change: JjChangeId,
        commitId: String,
        isEmpty: Bool,
        isImmutable: Bool = false,
        authorName: String,
        authorTimestamp: String,
        bookmarkLabels: [String] = [],
        description: String,
        graphLinesAfter: [String] = []
    ) {
        self.graphPrefix = graphPrefix
        self.change = change
        self.commitId = commitId
        self.isEmpty = isEmpty
        self.isImmutable = isImmutable
        self.authorName = authorName
        self.authorTimestamp = authorTimestamp
        self.bookmarkLabels = bookmarkLabels
        self.description = description
        self.graphLinesAfter = graphLinesAfter
    }

    public var rowIdentity: String {
        commitId.isEmpty ? change.full : commitId
    }

    public var actionRevset: String {
        commitId.isEmpty ? change.prefix : commitId
    }

    public var graphDisplayLines: [String] {
        [graphPrefix] + graphLinesAfter
    }

    public var graphDisplayColumnCharacterCount: Int {
        graphDisplayLines.map(\.trailingWhitespaceTrimmedCount).max() ?? 0
    }

    public var metadataDisplayItems: [String] {
        [change.prefix, commitId, authorName, authorTimestamp] + bookmarkLabels
    }

    private enum CodingKeys: String, CodingKey {
        case graphPrefix
        case change
        case commitId
        case isEmpty
        case isImmutable
        case authorName
        case authorTimestamp
        case bookmarkLabels
        case description
        case graphLinesAfter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        graphPrefix = try container.decode(String.self, forKey: .graphPrefix)
        change = try container.decode(JjChangeId.self, forKey: .change)
        commitId = try container.decode(String.self, forKey: .commitId)
        isEmpty = try container.decode(Bool.self, forKey: .isEmpty)
        isImmutable = try container.decodeIfPresent(Bool.self, forKey: .isImmutable) ?? false
        authorName = try container.decode(String.self, forKey: .authorName)
        authorTimestamp = try container.decode(String.self, forKey: .authorTimestamp)
        bookmarkLabels = try container.decodeIfPresent([String].self, forKey: .bookmarkLabels) ?? []
        description = try container.decode(String.self, forKey: .description)
        graphLinesAfter = try container.decodeIfPresent([String].self, forKey: .graphLinesAfter) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(graphPrefix, forKey: .graphPrefix)
        try container.encode(change, forKey: .change)
        try container.encode(commitId, forKey: .commitId)
        try container.encode(isEmpty, forKey: .isEmpty)
        try container.encode(isImmutable, forKey: .isImmutable)
        try container.encode(authorName, forKey: .authorName)
        try container.encode(authorTimestamp, forKey: .authorTimestamp)
        try container.encode(bookmarkLabels, forKey: .bookmarkLabels)
        try container.encode(description, forKey: .description)
        try container.encode(graphLinesAfter, forKey: .graphLinesAfter)
    }
}

private extension String {
    var trailingWhitespaceTrimmedCount: Int {
        var trimmedEnd = endIndex
        while trimmedEnd > startIndex {
            let previous = index(before: trimmedEnd)
            guard self[previous].isWhitespace else { break }
            trimmedEnd = previous
        }
        return distance(from: startIndex, to: trimmedEnd)
    }
}

public struct JjOperation: Hashable, Sendable, Codable {
    public let id: String
    public let timestamp: Date
    public let description: String

    public init(id: String, timestamp: Date, description: String) {
        self.id = id
        self.timestamp = timestamp
        self.description = description
    }
}

public enum JjFileChange: String, Sendable, Codable {
    case added = "A"
    case modified = "M"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
}

public struct JjStatusEntry: Hashable, Sendable, Codable {
    public let change: JjFileChange
    public let path: String
    public let oldPath: String?

    public init(change: JjFileChange, path: String, oldPath: String? = nil) {
        self.change = change
        self.path = path
        self.oldPath = oldPath
    }
}

public struct JjStatus: Sendable, Codable {
    public let workingCopy: JjChangeId
    public let parent: JjChangeId?
    public let workingCopySummary: String
    public let entries: [JjStatusEntry]
    public let hasConflicts: Bool

    public init(workingCopy: JjChangeId, parent: JjChangeId?, workingCopySummary: String, entries: [JjStatusEntry], hasConflicts: Bool) {
        self.workingCopy = workingCopy
        self.parent = parent
        self.workingCopySummary = workingCopySummary
        self.entries = entries
        self.hasConflicts = hasConflicts
    }
}

public struct JjConflict: Hashable, Sendable, Codable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct JjWorkspaceEntry: Hashable, Sendable, Codable {
    public let name: String
    public let workingCopy: JjChangeId

    public init(name: String, workingCopy: JjChangeId) {
        self.name = name
        self.workingCopy = workingCopy
    }
}

public struct JjVersion: Hashable, Sendable, Codable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: JjVersion, rhs: JjVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
}

public struct JjDiffFileStat: Hashable, Sendable, Codable {
    public let path: String
    public let additions: Int
    public let deletions: Int

    public init(path: String, additions: Int, deletions: Int) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
    }
}

public struct JjDiffStat: Sendable, Codable {
    public let files: [JjDiffFileStat]
    public let totalAdditions: Int
    public let totalDeletions: Int

    public init(files: [JjDiffFileStat], totalAdditions: Int, totalDeletions: Int) {
        self.files = files
        self.totalAdditions = totalAdditions
        self.totalDeletions = totalDeletions
    }
}

public struct JjShowOutput: Sendable, Codable {
    public let change: JjChangeId
    public let parents: [JjChangeId]
    public let description: String
    public let diffStat: JjDiffStat?

    public init(change: JjChangeId, parents: [JjChangeId], description: String, diffStat: JjDiffStat?) {
        self.change = change
        self.parents = parents
        self.description = description
        self.diffStat = diffStat
    }
}
