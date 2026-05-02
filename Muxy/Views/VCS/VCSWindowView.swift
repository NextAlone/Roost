import SwiftUI

struct VCSWindowView: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @State private var vcsStates: [WorktreeKey: VCSTabState] = [:]
    @State private var activeState: VCSTabState?
    @State private var syncTask: Task<Void, Never>?

    private var activeProject: Project? {
        guard let pid = appState.activeProjectID else { return nil }
        return projectStore.projects.first { $0.id == pid }
    }

    var body: some View {
        Group {
            if let state = activeState {
                VCSTabView(state: state, focused: true, onFocus: {})
            } else {
                Text("No project selected")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .preferredColorScheme(MuxyTheme.colorScheme)
        .onAppear {
            synchronizeState()
        }
        .onChange(of: appState.activeProjectID) {
            scheduleSynchronizeState()
        }
        .onChange(of: appState.activeWorktreeID) {
            scheduleSynchronizeState()
        }
        .onChange(of: projectStore.projects.map(\.id)) {
            scheduleSynchronizeState()
        }
        .onChange(of: worktreeStore.worktrees.mapValues { $0.map(\.id) }) {
            scheduleSynchronizeState()
        }
    }

    private func scheduleSynchronizeState() {
        syncTask?.cancel()
        syncTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            synchronizeState()
        }
    }

    private func synchronizeState() {
        vcsStates = vcsStates.filter { entry in
            worktreeStore.list(for: entry.key.projectID)
                .contains(where: { $0.id == entry.key.worktreeID })
        }

        guard let project = activeProject,
              let key = appState.activeWorktreeKey(for: project.id)
        else {
            activeState = nil
            return
        }

        if let existing = vcsStates[key] {
            activeState = existing
            return
        }

        let worktreePath = worktreeStore
            .worktree(projectID: project.id, worktreeID: key.worktreeID)?
            .path ?? project.path
        let state = VCSTabState(projectPath: worktreePath)
        vcsStates[key] = state
        activeState = state
    }
}
