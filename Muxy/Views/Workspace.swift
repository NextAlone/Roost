import SwiftUI

struct Workspace: View {
    let project: Project
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(project: project)
            terminal
        }
        .onReceive(NotificationCenter.default.publisher(for: .muxyCreateNewTab)) { n in
            guard let id = n.userInfo?["projectID"] as? UUID, id == project.id else { return }
            appState.createTab(for: project)
        }
        .onReceive(NotificationCenter.default.publisher(for: .muxySplitPane)) { n in
            guard let id = n.userInfo?["projectID"] as? UUID, id == project.id,
                  let direction = n.userInfo?["direction"] as? SplitDirection,
                  let tab = appState.activeTab(for: project.id) else { return }
            tab.splitFocusedPane(direction: direction, projectPath: project.path)
        }
    }

    @ViewBuilder
    private var terminal: some View {
        if let tab = appState.activeTab(for: project.id) {
            PaneTree(tab: tab, projectPath: project.path)
                .id(tab.id)
        }
    }
}
