import Foundation

public enum SessionLifecycleState: String, Sendable, Codable, Hashable, CaseIterable {
    case preparing
    case running
    case exited
}
