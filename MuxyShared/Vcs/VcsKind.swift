import Foundation

public enum VcsKind: String, Sendable, Codable, Hashable, CaseIterable {
    case git
    case jj
}
