import Foundation

public enum AgentDetectionState: String, Sendable, Codable, Equatable {
    case idle
    case working
    case blocked
    case unknown

    public var label: String {
        switch self {
        case .idle: "idle"
        case .working: "working"
        case .blocked: "blocked"
        case .unknown: "unknown"
        }
    }
}

public struct AgentDetectionResult: Sendable, Codable, Equatable {
    public let state: AgentDetectionState
    public let agentLabel: String?

    public init(state: AgentDetectionState, agentLabel: String?) {
        self.state = state
        self.agentLabel = agentLabel
    }
}

public protocol AgentDetector: Sendable {
    var agentLabel: String { get }
    func detect(screenContent: String) -> AgentDetectionState
}
