import Foundation

public enum SessionLifecycleState: String, Sendable, Codable, Hashable, CaseIterable {
    case running
    case exited
}
