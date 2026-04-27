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

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Image(systemName: agentKind.iconSystemName)
                    .font(.system(size: 10))
                    .foregroundStyle(isActive ? MuxyTheme.accent : MuxyTheme.fgDim)
                    .frame(width: 12)

                Text(tab.title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? MuxyTheme.fg : MuxyTheme.fgMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(agentKind.displayName): \(tab.title)")
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isActive {
            MuxyTheme.accentSoft
        } else if hovered {
            MuxyTheme.hover
        } else {
            Color.clear
        }
    }
}
