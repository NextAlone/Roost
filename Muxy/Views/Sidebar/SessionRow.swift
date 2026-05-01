import MuxyShared
import SwiftUI

struct SessionRow: View {
    let tab: TerminalTab
    let isActive: Bool
    let onSelect: () -> Void

    @State private var hovered = false

    private var agentKind: AgentKind {
        tab.content.pane?.agentKind ?? .terminal
    }

    private var activityState: AgentActivityState {
        tab.content.pane?.activityState ?? .running
    }

    private var showsActivityBadge: Bool {
        agentKind != .terminal
    }

    @ViewBuilder
    private var lifecycleDot: some View {
        switch tab.content.pane?.lastState ?? .running {
        case .running:
            EmptyView()
        case .exited:
            Circle()
                .fill(MuxyTheme.fgDim)
                .frame(width: 5, height: 5)
                .accessibilityLabel("Exited")
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                AgentKindIconView(
                    kind: agentKind,
                    size: 11,
                    color: isActive ? MuxyTheme.accent : MuxyTheme.fgDim
                )
                .frame(width: 12)

                Text(tab.title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if showsActivityBadge {
                    AgentActivityBadge(state: activityState)
                } else {
                    lifecycleDot
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if showsActivityBadge {
            return "\(agentKind.displayName): \(tab.title), \(activityState.accessibilityLabel)"
        }
        return "\(agentKind.displayName): \(tab.title)"
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isActive {
            MuxyTheme.accentSoft
        } else if showsActivityBadge, activityState == .needsInput {
            hovered ? MuxyTheme.diffRemoveBg.opacity(0.72) : MuxyTheme.diffRemoveBg.opacity(0.48)
        } else if hovered {
            MuxyTheme.hover
        } else {
            Color.clear
        }
    }
}
