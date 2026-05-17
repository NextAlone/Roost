import Foundation

public struct AgentDetectionStateMachine: Sendable {
    public var currentState: AgentDetectionState = .unknown
    private var pendingState: AgentDetectionState?
    private var pendingCount: Int = 0
    private var lastClaudeWorkingAt: Date?

    private static let claudeWorkingHold: TimeInterval = 1.2
    private static let confirmationThreshold: Int = 2

    public init() {}

    public mutating func observe(rawState: AgentDetectionState, agentLabel: String?, now: Date = Date()) -> AgentDetectionState? {
        let stabilized = stabilize(rawState, agentLabel: agentLabel, now: now)
        if stabilized == currentState {
            pendingState = nil
            pendingCount = 0
            return nil
        }
        if let pending = pendingState, stabilized == pending {
            pendingCount += 1
            if pendingCount < Self.confirmationThreshold {
                return nil
            }
        } else {
            pendingState = stabilized
            pendingCount = 1
            if pendingCount < Self.confirmationThreshold {
                return nil
            }
        }
        pendingState = nil
        pendingCount = 0
        let previous = currentState
        currentState = stabilized
        if stabilized != previous {
            return stabilized
        }
        return nil
    }

    public mutating func reset() {
        currentState = .unknown
        pendingState = nil
        pendingCount = 0
        lastClaudeWorkingAt = nil
    }

    private mutating func stabilize(_ raw: AgentDetectionState, agentLabel: String?, now: Date) -> AgentDetectionState {
        guard agentLabel == "claude" else { return raw }
        switch raw {
        case .working:
            lastClaudeWorkingAt = now
            return .working
        case .blocked:
            return .blocked
        case .idle where currentState == .working:
            if let lastWorking = lastClaudeWorkingAt,
               now.timeIntervalSince(lastWorking) < Self.claudeWorkingHold
            {
                return .working
            }
            return .idle
        default:
            return raw
        }
    }
}
