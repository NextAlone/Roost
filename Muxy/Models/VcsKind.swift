import Foundation

enum VcsKind: String, Sendable, Codable, Hashable, CaseIterable {
    case git
    case jj

    static let `default`: VcsKind = .git
}
