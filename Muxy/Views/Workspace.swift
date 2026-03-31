import SwiftUI

struct TerminalArea: View {
    let project: Project
    @Environment(AppState.self) private var appState

    var body: some View {
        ZStack {
            ForEach(appState.tabsForProject(project.id)) { tab in
                let isActive = tab.id == appState.activeTabID[project.id]
                PaneTree(tab: tab, projectPath: project.path, isActiveTab: isActive)
                    .id(tab.id)
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
            }
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
}
