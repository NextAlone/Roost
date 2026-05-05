import MuxyShared
import SwiftUI

enum AgentActivityStatusBadgeLayout {
    static let diameter: CGFloat = 13
    static let height: CGFloat = 18
}

struct AgentActivityStatusBadge: View {
    let state: AgentActivityState

    var body: some View {
        ZStack {
            Circle()
                .fill(MuxyTheme.fgDim.opacity(0.26))
                .frame(
                    width: AgentActivityStatusBadgeLayout.diameter,
                    height: AgentActivityStatusBadgeLayout.diameter
                )
            AgentActivityStatusIcon(state: state)
                .id(state.rawValue)
        }
        .frame(
            width: AgentActivityStatusBadgeLayout.diameter,
            height: AgentActivityStatusBadgeLayout.height
        )
    }
}

struct AgentActivityStatusIcon: View {
    let state: AgentActivityState

    var body: some View {
        AgentActivityPulsingStatusIcon(style: AgentActivityStatusPulseStyle(state: state))
    }
}

struct AgentActivityStatusPulseStyle: Equatable {
    let state: AgentActivityState

    var breathes: Bool {
        switch state {
        case .running,
             .needsInput,
             .completed:
            true
        case .idle,
             .exited:
            false
        }
    }

    var duration: Double {
        1.24
    }

    var restingDiameter: CGFloat {
        switch state {
        case .running: 7
        case .needsInput: 6
        case .completed: 8
        case .idle: 6
        case .exited: 9
        }
    }

    var expandedDiameter: CGFloat {
        switch state {
        case .running,
             .needsInput,
             .completed:
            AgentActivityStatusBadgeLayout.diameter * 0.94
        case .idle: restingDiameter
        case .exited: restingDiameter
        }
    }

    var expandedOpacity: Double {
        breathes ? 0.38 : 0.92
    }
}

private struct AgentActivityPulsingStatusIcon: View {
    let style: AgentActivityStatusPulseStyle
    @State private var expanded = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: style.restingDiameter, height: style.restingDiameter)
            .scaleEffect(scale)
            .opacity(opacity)
            .animation(animation, value: expanded)
            .onAppear {
                expanded = style.breathes
            }
    }

    private var color: Color {
        switch style.state {
        case .running: MuxyTheme.accent
        case .needsInput: MuxyTheme.diffRemoveFg
        case .completed: MuxyTheme.diffAddFg
        case .idle: MuxyTheme.fgDim.opacity(0.45)
        case .exited: MuxyTheme.fgDim
        }
    }

    private var scale: CGFloat {
        guard style.breathes, expanded else { return 1 }
        return style.expandedDiameter / style.restingDiameter
    }

    private var opacity: Double {
        guard style.breathes, expanded else { return 0.92 }
        return style.expandedOpacity
    }

    private var animation: Animation? {
        guard style.breathes else { return nil }
        return .easeInOut(duration: style.duration).repeatForever(autoreverses: true)
    }
}

struct AgentActivityDotStack: View {
    let dots: [SidebarAgentActivityDot]

    var body: some View {
        HStack(spacing: -4) {
            ForEach(dots) { dot in
                AgentActivityStackDot(state: dot.state)
            }
        }
        .frame(height: AgentActivityStatusBadgeLayout.height)
        .help(helpText)
        .accessibilityLabel(helpText)
    }

    private var helpText: String {
        let parts: [String] = AgentActivityState.allCases.compactMap { state in
            let count = dots.count { $0.state == state }
            guard count > 0 else { return nil }
            return "\(count) \(state.accessibilityLabel.lowercased())"
        }
        return parts.joined(separator: ", ")
    }
}

struct AgentActivityStackDot: View {
    let state: AgentActivityState

    var body: some View {
        AgentActivityStatusBadge(state: state)
    }
}
