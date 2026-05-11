import SwiftUI

struct NewWorkspaceButton: View {
    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    let expanded: Bool
    @State private var showCreateSheet = false

    private var targetProject: Project? {
        guard let id = appState.activeProjectID, id != Project.scratchID else { return nil }
        return projectStore.projects.first { $0.id == id }
    }

    var body: some View {
        Button {
            guard targetProject != nil else { return }
            showCreateSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                if expanded {
                    Text("New Workspace")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(targetProject == nil ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(targetProject == nil)
        .help(targetProject == nil ? "Select a project first" : "New Workspace in \(targetProject?.name ?? "")")
        .popover(isPresented: $showCreateSheet, arrowEdge: .trailing) {
            if let project = targetProject {
                CreateWorktreeSheet(project: project) { _ in
                    showCreateSheet = false
                }
            }
        }
    }
}
