import Foundation

public enum AgentActivityState: String, Sendable, Codable, Hashable, CaseIterable {
    case running
    case needsInput
    case idle
    case completed
    case exited

    public var sidebarLabel: String {
        switch self {
        case .running: "RUN"
        case .needsInput: "WAIT"
        case .idle: "IDLE"
        case .completed: "DONE"
        case .exited: "EXIT"
        }
    }

    public var accessibilityLabel: String {
        switch self {
        case .running: "Running"
        case .needsInput: "Needs input"
        case .idle: "Idle"
        case .completed: "Completed"
        case .exited: "Exited"
        }
    }
}
