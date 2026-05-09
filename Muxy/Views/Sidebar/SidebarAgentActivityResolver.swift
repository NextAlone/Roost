import Foundation
import MuxyShared

struct SidebarAgentActivityDot: Equatable, Identifiable {
    let index: Int
    let state: AgentActivityState
    let previousState: AgentActivityState?

    var id: String {
        "\(index)-\(state.rawValue)-\(previousState?.rawValue ?? "nil")"
    }
}

struct SidebarAgentActivitySummary: Equatable {
    let dominantState: AgentActivityState
    let dominantPreviousState: AgentActivityState?
    let agentEntries: [AgentActivityEntry]

    struct AgentActivityEntry: Equatable {
        let state: AgentActivityState
        let previousState: AgentActivityState?
    }

    var agentCount: Int {
        agentEntries.count
    }

    var dots: [SidebarAgentActivityDot] {
        agentEntries.enumerated().map { index, entry in
            SidebarAgentActivityDot(index: index, state: entry.state, previousState: entry.previousState)
        }
    }

    var showsSidebarStatusDots: Bool {
        !agentEntries.isEmpty
    }

    func count(for state: AgentActivityState) -> Int {
        agentEntries.count { $0.state == state }
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
        let entries: [SidebarAgentActivitySummary.AgentActivityEntry] = tabs
            .compactMap(\.content.pane)
            .filter { $0.agentKind != .terminal }
            .map { .init(state: $0.activityState, previousState: $0.previousActivityState) }
        guard !entries.isEmpty else { return nil }
        guard let dominantState = AgentActivityState.sidebarPriority.first(where: { state in
            entries.contains(where: { $0.state == state })
        })
        else { return nil }
        let dominantPrevious = entries
            .first(where: { $0.state == dominantState })?
            .previousState
        return SidebarAgentActivitySummary(
            dominantState: dominantState,
            dominantPreviousState: dominantPrevious,
            agentEntries: entries
        )
    }
}

extension AgentActivityState {
    static var sidebarPriority: [AgentActivityState] {
        [.awaiting, .running, .completed, .idle, .exited]
    }

    var acknowledgedSidebarState: AgentActivityState {
        switch self {
        case .completed:
            .idle
        case .awaiting,
             .running,
             .idle,
             .exited:
            self
        }
    }
}
