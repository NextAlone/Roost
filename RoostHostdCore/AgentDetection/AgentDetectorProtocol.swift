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

public enum AgentScreenSignal: String, Sendable, Codable, Equatable {
    case idlePrompt
    case workingIndicator
    case blockedPrompt
    case completionLine
    case interruptedPrompt
    case unknown
}

public struct AgentScreenEvidence: Sendable, Codable, Equatable {
    public let state: AgentDetectionState
    public let signal: AgentScreenSignal

    public init(state: AgentDetectionState, signal: AgentScreenSignal) {
        self.state = state
        self.signal = signal
    }
}

public struct AgentDetectionResult: Sendable, Codable, Equatable {
    public let state: AgentDetectionState
    public let agentLabel: String?
    public let signal: AgentScreenSignal

    public init(state: AgentDetectionState, agentLabel: String?, signal: AgentScreenSignal = .unknown) {
        self.state = state
        self.agentLabel = agentLabel
        self.signal = signal
    }
}

public protocol AgentDetector: Sendable {
    var agentLabel: String { get }
    func detect(screenContent: String) -> AgentDetectionState
    func detectEvidence(screenContent: String) -> AgentScreenEvidence
}

public extension AgentDetector {
    func detect(screenContent: String) -> AgentDetectionState {
        detectEvidence(screenContent: screenContent).state
    }
}
