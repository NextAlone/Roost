import SwiftUI

enum PendingAgentsBannerLayout {
    static let horizontalInset: CGFloat = ExpandedWorktreeRowLayout.projectTitleLeadingEdge
    static let verticalPadding: CGFloat = 1
    static let dotSize: CGFloat = 7
}

struct PendingAgentsBanner: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @State private var showingPopover = false
    @State private var hovered = false

    var body: some View {
        let summaries = resolvedSummaries(from: appState.agentAttentionPanes)
        if summaries.isEmpty {
            EmptyView()
        } else {
            Button {
                showingPopover = true
            } label: {
                HStack(spacing: 6) {
                    AttentionDotStrip(kinds: summaries.map(\.attentionKind))
                    Text(Self.summaryText(for: summaries.map(\.attentionKind)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MuxyTheme.fgMuted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fgDim)
                }
                .padding(.leading, PendingAgentsBannerLayout.horizontalInset)
                .padding(.trailing, ExpandedWorktreeRowLayout.trailingContentInset)
                .padding(.vertical, PendingAgentsBannerLayout.verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovered ? MuxyTheme.hover : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
                PendingAgentsPopover(summaries: summaries) { paneID in
                    showingPopover = false
                    focus(paneID: paneID)
                }
                .frame(minWidth: 240)
            }
        }
    }

    static func summaryText(for kinds: [AgentAttentionKind]) -> String {
        AgentAttentionKind.allCases.compactMap { kind in
            let count = kinds.count { $0 == kind }
            guard count > 0 else { return nil }
            return "\(count) \(kind.label)"
        }.joined(separator: " · ")
    }

    private func resolvedSummaries(from summaries: [AwaitingPaneSummary]) -> [AwaitingPaneSummary] {
        summaries.map { summary in
            guard summary.projectName.isEmpty,
                  let name = projectStore.projects.first(where: { $0.id == summary.projectID })?.name
            else { return summary }
            return AwaitingPaneSummary(
                id: summary.id,
                paneID: summary.paneID,
                projectID: summary.projectID,
                worktreeID: summary.worktreeID,
                paneTitle: summary.paneTitle,
                projectName: name,
                workspaceName: summary.workspaceName,
                attentionKind: summary.attentionKind
            )
        }
    }

    private func focus(paneID: UUID) {
        appState.focusPane(paneID: paneID)
        appState.acknowledgeAgentActivity(paneID: paneID)
    }
}

@MainActor
private extension AgentAttentionKind {
    var shortLabel: String {
        switch self {
        case .needInput: "INPUT"
        case .wait: "WAIT"
        case .done: "DONE"
        }
    }

    var color: Color {
        switch self {
        case .needInput: MuxyTheme.diffRemoveFg
        case .wait: MuxyTheme.warning
        case .done: MuxyTheme.diffAddFg
        }
    }
}

private struct AttentionDotStrip: View {
    let kinds: [AgentAttentionKind]

    var body: some View {
        HStack(spacing: -3) {
            ForEach(AgentAttentionKind.allCases, id: \.self) { kind in
                let count = kinds.count { $0 == kind }
                if count > 0 {
                    Circle()
                        .fill(kind.color)
                        .frame(width: PendingAgentsBannerLayout.dotSize, height: PendingAgentsBannerLayout.dotSize)
                }
            }
        }
        .frame(width: 20, alignment: .leading)
    }
}

private struct AttentionKindBadge: View {
    let kind: AgentAttentionKind

    var body: some View {
        Text(kind.shortLabel)
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .foregroundStyle(kind.color)
            .frame(width: 42, height: 16)
            .background(kind.color.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(kind.color.opacity(0.2), lineWidth: 0.5)
            }
    }
}

private struct PendingAgentsPopover: View {
    let summaries: [AwaitingPaneSummary]
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(summaries) { summary in
                Button {
                    onSelect(summary.paneID)
                } label: {
                    HStack(spacing: 8) {
                        AttentionKindBadge(kind: summary.attentionKind)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.paneTitle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MuxyTheme.fg)
                            let subtitle = [summary.projectName, summary.workspaceName]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · ")
                            if !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(MuxyTheme.fgMuted)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
        .padding(.vertical, 4)
    }
}
