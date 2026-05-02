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
        }
        .frame(
            width: AgentActivityStatusBadgeLayout.diameter,
            height: AgentActivityStatusBadgeLayout.height
        )
    }
}

struct AgentActivityStatusIcon: View {
    let state: AgentActivityState
    var runningSize: CGFloat = 11
    var waitingSize: CGFloat = 6

    var body: some View {
        switch state {
        case .running:
            AgentActivityRunningStatusIcon(size: runningSize)
        case .needsInput:
            AgentActivityWaitingStatusIcon(size: waitingSize)
        case .completed:
            Circle()
                .fill(MuxyTheme.diffAddFg)
                .frame(width: 9, height: 9)
        case .idle:
            Circle()
                .fill(MuxyTheme.fgDim.opacity(0.45))
                .frame(width: 6, height: 6)
        case .exited:
            Circle()
                .fill(MuxyTheme.fgDim)
                .frame(width: 9, height: 9)
        }
    }
}

private struct AgentActivityRunningStatusIcon: View {
    let size: CGFloat
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.18, to: 0.82)
            .stroke(
                MuxyTheme.accent,
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1.0).repeatForever(autoreverses: false), value: spinning)
            .onAppear {
                spinning = true
            }
    }
}

private struct AgentActivityWaitingStatusIcon: View {
    let size: CGFloat
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(MuxyTheme.diffRemoveFg.opacity(0.18))
                .frame(width: size * 2.6, height: size * 2.6)
                .scaleEffect(pulsing ? 1.2 : 0.72)
                .opacity(pulsing ? 0.18 : 0.55)
                .animation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true), value: pulsing)
            Circle()
                .fill(MuxyTheme.diffRemoveFg)
                .frame(width: size, height: size)
        }
        .onAppear {
            pulsing = true
        }
    }
}
