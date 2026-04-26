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
    public let description: String
    public let entries: [JjStatusEntry]
    public let hasConflicts: Bool

    public init(workingCopy: JjChangeId, parent: JjChangeId?, description: String, entries: [JjStatusEntry], hasConflicts: Bool) {
        self.workingCopy = workingCopy
        self.parent = parent
        self.description = description
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
