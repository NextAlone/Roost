import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @State private var sidebarWidth: CGFloat = 260

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(width: sidebarWidth)

            SidebarDragHandle(width: $sidebarWidth)

            ZStack {
                MuxyTheme.bg
                if let pid = appState.activeProjectID,
                   let project = projectStore.projects.first(where: { $0.id == pid }) {
                    Workspace(project: project)
                } else {
                    WelcomeView()
                }
            }
        }
        .background(MuxyTheme.bg)
        .edgesIgnoringSafeArea(.top)
    }
}
