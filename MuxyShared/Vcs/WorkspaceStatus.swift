import Foundation

public enum WorkspaceStatus: String, Sendable, Codable, Hashable, CaseIterable {
    case clean
    case dirty
    case conflicted
    case unknown

    public func dominates(_ other: WorkspaceStatus) -> Bool {
        rank > other.rank
    }

    private var rank: Int {
        switch self {
        case .unknown: 0
        case .clean: 1
        case .dirty: 2
        case .conflicted: 3
        }
    }
}
