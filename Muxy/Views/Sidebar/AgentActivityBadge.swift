import MuxyShared
import SwiftUI

struct AgentActivityBadge: View {
    let state: AgentActivityState

    var body: some View {
        HStack(spacing: 3) {
            icon

            Text(state.sidebarLabel)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(foreground)
        .frame(width: 48, height: 16)
        .background {
            Capsule()
                .fill(background)
        }
        .overlay {
            Capsule()
                .stroke(border, lineWidth: 0.5)
        }
        .accessibilityLabel(state.accessibilityLabel)
        .help(state.accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        if state == .running {
            AgentRunningActivityIcon()
        } else {
            Image(systemName: symbolName)
                .font(.system(size: iconSize, weight: .bold))
        }
    }

    private var symbolName: String {
        switch state {
        case .running: "arrow.triangle.2.circlepath"
        case .needsInput: "exclamationmark"
        case .idle: "pause.fill"
        case .completed: "checkmark"
        case .exited: "xmark"
        }
    }

    private var iconSize: CGFloat {
        state == .running ? 7 : 8
    }

    private var foreground: Color {
        switch state {
        case .running: MuxyTheme.accent
        case .needsInput: MuxyTheme.diffRemoveFg
        case .idle: MuxyTheme.fgMuted
        case .completed: MuxyTheme.diffAddFg
        case .exited: MuxyTheme.fgDim
        }
    }

    private var background: AnyShapeStyle {
        switch state {
        case .needsInput:
            AnyShapeStyle(LinearGradient(
                colors: [
                    MuxyTheme.diffRemoveFg.opacity(0.28),
                    MuxyTheme.diffRemoveFg.opacity(0.12),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ))
        case .completed:
            AnyShapeStyle(MuxyTheme.diffAddFg.opacity(0.14))
        case .running:
            AnyShapeStyle(MuxyTheme.accent.opacity(0.12))
        case .idle:
            AnyShapeStyle(MuxyTheme.surface)
        case .exited:
            AnyShapeStyle(MuxyTheme.surface)
        }
    }

    private var border: Color {
        switch state {
        case .needsInput: MuxyTheme.diffRemoveFg.opacity(0.22)
        case .completed: MuxyTheme.diffAddFg.opacity(0.2)
        case .running: MuxyTheme.accent.opacity(0.18)
        case .idle,
             .exited: MuxyTheme.border
        }
    }
}

private struct AgentRunningActivityIcon: View {
    @State private var spinning = false

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 7, weight: .bold))
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spinning)
            .onAppear {
                spinning = true
            }
    }
}
