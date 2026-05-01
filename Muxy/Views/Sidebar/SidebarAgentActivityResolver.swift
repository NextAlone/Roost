import Foundation
import MuxyShared

enum SidebarAgentActivityResolver {
    @MainActor
    static func activityState(tabs: [TerminalTab], activeTabID: UUID?) -> AgentActivityState? {
        let panes = tabs.compactMap(\.content.pane).filter { $0.agentKind != .terminal }
        guard !panes.isEmpty else { return nil }

        if let activeTabID,
           let activePane = tabs.first(where: { $0.id == activeTabID })?.content.pane,
           activePane.agentKind != .terminal,
           activePane.activityState != .completed,
           activePane.activityState != .exited
        {
            return activePane.activityState
        }

        for state in AgentActivityState.sidebarPriority where panes.contains(where: { $0.activityState == state }) {
            return state
        }
        return nil
    }
}

private extension AgentActivityState {
    static var sidebarPriority: [AgentActivityState] {
        [.needsInput, .running, .idle, .completed, .exited]
    }
}
