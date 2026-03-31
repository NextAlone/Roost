import SwiftUI

struct Sidebar: View {
    let width: CGFloat
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                IconButton(symbol: "plus", size: 11) { addProject() }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(projectStore.projects) { project in
                        ProjectRow(
                            project: project,
                            selected: project.id == appState.activeProjectID
                        ) {
                            appState.activeProjectID = project.id
                            appState.ensureTabExists(for: project)
                        } onRemove: {
                            appState.removeProject(project.id)
                            projectStore.remove(id: project.id)
                        }
                    }
                }
                .padding(6)
            }
        }
        .frame(width: width)
        .background(MuxyTheme.surfaceDim)
    }

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a project folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let project = Project(
            name: url.lastPathComponent,
            path: url.path(percentEncoded: false),
            sortOrder: projectStore.projects.count
        )
        projectStore.add(project)
        appState.activeProjectID = project.id
    }
}
