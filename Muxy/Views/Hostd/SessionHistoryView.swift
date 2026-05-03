import MuxyShared
import SwiftUI

struct SessionHistoryView: View {
    let onRelaunch: (SessionRecord) -> Void
    let onClose: () -> Void

    @Environment(\.roostHostdClient) private var hostdClient
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var store = SessionHistoryStore()

    private let limit = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            footer
        }
        .padding(16)
        .frame(width: 560, height: 480)
        .task(id: hostdClient != nil) {
            await refresh()
        }
    }

    private var header: some View {
        HStack {
            Text("Session History")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button {
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(store.isLoading)
            .accessibilityLabel("Refresh")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.errorMessage {
            Text(error)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.diffRemoveFg)
        } else if store.isLoading, store.records.isEmpty {
            ProgressView().controlSize(.small)
        } else if store.records.isEmpty {
            Text("No sessions yet")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgDim)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 24)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.records.prefix(limit), id: \.id) { record in
                        row(record: record)
                    }
                }
            }
        }
    }

    private func row(record: SessionRecord) -> some View {
        HStack(spacing: 6) {
            AgentKindIconView(kind: record.agentKind, size: 12, color: MuxyTheme.fgDim)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.agentKind.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MuxyTheme.fg)
                Text(record.workspacePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(stateLabel(record.lastState))
                .font(.system(size: 10))
                .foregroundStyle(stateColor(record.lastState))
            Button("Re-launch") {
                onRelaunch(record)
            }
            .buttonStyle(.borderless)
            .disabled(!canRelaunch(record))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private func stateLabel(_ state: SessionLifecycleState) -> String {
        switch state {
        case .running: "running"
        case .exited: "exited"
        }
    }

    private func stateColor(_ state: SessionLifecycleState) -> Color {
        switch state {
        case .running: MuxyTheme.diffAddFg
        case .exited: MuxyTheme.fgDim
        }
    }

    private func canRelaunch(_ record: SessionRecord) -> Bool {
        guard projectStore.projects.contains(where: { $0.id == record.projectID }) else { return false }
        let worktrees = worktreeStore.worktrees[record.projectID] ?? []
        return worktrees.contains(where: { $0.id == record.worktreeID })
    }

    private var footer: some View {
        HStack {
            Button("Prune Exited") {
                Task { await store.prune() }
            }
            .disabled(store.isLoading)
            Spacer()
            Button("Close") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func refresh() async {
        store.updateClient(hostdClient)
        if let hostdClient {
            await appState.recordRestoredAgentSessions(hostdClient: hostdClient)
        }
        await store.refresh()
    }
}
