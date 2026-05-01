import Foundation
import MuxyShared

struct AgentActivitySocketEvent: Equatable {
    let sourceType: String
    let activityState: AgentActivityState?

    static func parse(type rawType: String) -> AgentActivitySocketEvent {
        let trimmed = rawType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let separatorIndex = trimmed.lastIndex(of: ":") else {
            return AgentActivitySocketEvent(sourceType: trimmed, activityState: nil)
        }

        let source = String(trimmed[..<separatorIndex])
        let suffix = String(trimmed[trimmed.index(after: separatorIndex)...])
        guard !source.isEmpty, let state = activityState(from: suffix) else {
            return AgentActivitySocketEvent(sourceType: trimmed, activityState: nil)
        }
        return AgentActivitySocketEvent(sourceType: source, activityState: state)
    }

    private static func activityState(from suffix: String) -> AgentActivityState? {
        switch suffix {
        case "running":
            .running
        case "needs_input",
             "needsInput",
             "permission",
             "notification":
            .needsInput
        case "idle":
            .idle
        case "completed",
             "complete",
             "done",
             "stop",
             "stopped":
            .completed
        case "exited",
             "exit":
            .exited
        default:
            nil
        }
    }
}
