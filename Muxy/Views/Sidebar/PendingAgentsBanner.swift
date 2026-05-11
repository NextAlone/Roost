import SwiftUI

struct PendingAgentsBanner: View {
    @Environment(AppState.self) private var appState
    @State private var showingPopover = false

    var body: some View {
        let awaiting = appState.awaitingPanes
        if awaiting.isEmpty {
            EmptyView()
        } else {
            Button {
                showingPopover = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.yellow)
                    Text("\(awaiting.count) agent\(awaiting.count == 1 ? "" : "s") awaiting")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.yellow.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingPopover, arrowEdge: .trailing) {
                PendingAgentsPopover(summaries: awaiting) { paneID in
                    showingPopover = false
                    focus(paneID: paneID)
                }
                .frame(minWidth: 240)
            }
        }
    }

    private func focus(paneID: UUID) {
        appState.focusPane(paneID: paneID)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.paneTitle)
                            .font(.system(size: 12, weight: .semibold))
                        let subtitle = [summary.projectName, summary.workspaceName]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
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
