import SwiftUI

struct ProjectSidebar: View {
    @ObservedObject var store: ProjectStore
    @Binding var selection: Project.ID?
    let unreadProjectIDs: Set<Project.ID>
    let scratchHasUnread: Bool
    let scratchHasSessions: Bool
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if store.projects.isEmpty && !scratchHasSessions {
                emptyState
            } else {
                List(selection: $selection) {
                    if scratchHasSessions {
                        ScratchRow(isUnread: scratchHasUnread)
                            .tag(Project.ID?.none as Project.ID?)
                    }
                    ForEach(store.projects) { project in
                        ProjectRow(
                            project: project,
                            isUnread: unreadProjectIDs.contains(project.id)
                        )
                        .tag(Project.ID?.some(project.id) as Project.ID?)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.remove(project.id)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()

            HStack {
                Button(action: onAdd) {
                    Label("Add project", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.bar)
        }
        .navigationTitle("Projects")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No projects yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScratchRow: View {
    let isUnread: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            }
            Image(systemName: "tray")
                .foregroundStyle(.secondary)
            Text("Scratch")
                .font(.body)
        }
        .padding(.vertical, 2)
    }
}

private struct ProjectRow: View {
    let project: Project
    let isUnread: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isUnread {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.body)
                    .lineLimit(1)
                Text(project.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }
}
