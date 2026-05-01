import Foundation
import MuxyShared

struct SidebarAgentActivityDot: Equatable, Identifiable {
    let index: Int
    let state: AgentActivityState

    var id: String {
        "\(index)-\(state.rawValue)"
    }
}

struct SidebarAgentActivitySummary: Equatable {
    let dominantState: AgentActivityState
    let agentStates: [AgentActivityState]

    var agentCount: Int {
        agentStates.count
    }

    var dots: [SidebarAgentActivityDot] {
        agentStates.enumerated().map { index, state in
            SidebarAgentActivityDot(index: index, state: state)
        }
    }

    func count(for state: AgentActivityState) -> Int {
        agentStates.count { $0 == state }
    }

    var accessibilityLabel: String {
        if agentCount == 1 {
            return "Agent \(dominantState.accessibilityLabel.lowercased())"
        }
        let parts: [String] = AgentActivityState.sidebarPriority.compactMap { state in
            let count = count(for: state)
            guard count > 0 else { return nil }
            return "\(count) \(state.accessibilityLabel.lowercased())"
        }
        return "\(agentCount) agents, \(parts.joined(separator: ", "))"
    }
}

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

    @MainActor
    static func summary(tabs: [TerminalTab], activeTabID _: UUID?) -> SidebarAgentActivitySummary? {
        let agentStates = tabs
            .compactMap(\.content.pane)
            .filter { $0.agentKind != .terminal }
            .map(\.activityState)
        guard !agentStates.isEmpty else { return nil }
        guard let dominantState = AgentActivityState.sidebarPriority.first(where: { state in
            agentStates.contains(state)
        })
        else { return nil }
        return SidebarAgentActivitySummary(dominantState: dominantState, agentStates: agentStates)
    }
}

extension AgentActivityState {
    static var sidebarPriority: [AgentActivityState] {
        [.needsInput, .running, .completed, .idle, .exited]
    }

    var acknowledgedSidebarState: AgentActivityState {
        switch self {
        case .completed:
            .idle
        case .needsInput,
             .running,
             .idle,
             .exited:
            self
        }
    }
}
