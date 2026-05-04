import SwiftUI

struct StartupView: View {
    let project: Project?
    let worktree: Worktree?

    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 40)
            Image(systemName: project == nil ? "folder.badge.plus" : "macwindow.badge.plus")
                .font(.system(size: 30))
                .foregroundStyle(MuxyTheme.fgMuted)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(MuxyTheme.fgMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            HStack(spacing: 10) {
                if let project, let worktree {
                    Button {
                        appState.selectWorktree(projectID: project.id, worktree: worktree)
                    } label: {
                        Label("New Tab", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if project == nil {
                    Button {
                        openProject()
                    } label: {
                        Label("Open Project...", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        openProject()
                    } label: {
                        Label("Open Project...", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if project == nil, !recentProjects.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Projects")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fgDim)
                    VStack(spacing: 4) {
                        ForEach(recentProjects) { item in
                            Button {
                                select(item)
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 12))
                                        .foregroundStyle(MuxyTheme.fgMuted)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(item.name)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(MuxyTheme.fg)
                                            .lineLimit(1)
                                        Text(item.path)
                                            .font(.system(size: 10))
                                            .foregroundStyle(MuxyTheme.fgDim)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .frame(width: 360, alignment: .leading)
                                .background(MuxyTheme.hover, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 4)
            }

            Spacer(minLength: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        if let project {
            return project.name
        }
        return "Roost"
    }

    private var subtitle: String {
        if project != nil {
            return "No tabs are open in this project."
        }
        return "Select a project or open a folder."
    }

    private var recentProjects: [Project] {
        Array(projectStore.projects.prefix(5))
    }

    private func select(_ project: Project) {
        guard let worktree = worktreeStore.preferred(
            for: project.id,
            matching: appState.activeWorktreeID[project.id]
        )
        else { return }
        appState.selectProject(project, worktree: worktree)
    }

    private func openProject() {
        ProjectOpenService.openProject(
            appState: appState,
            projectStore: projectStore,
            worktreeStore: worktreeStore
        )
    }
}
