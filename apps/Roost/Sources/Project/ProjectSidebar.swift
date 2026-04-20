import SwiftUI

struct ProjectSidebar: View {
    @ObservedObject var store: ProjectStore
    @Binding var selection: Project.ID?
    let unreadProjectIDs: Set<Project.ID>
    let scratchHasUnread: Bool
    let scratchSessionCount: Int
    let sessionCountByProject: [Project.ID: Int]
    /// M5: latest setup/teardown hook failure per project, keyed by ID.
    /// Shown as a ⚠ icon with a tooltip on the project row.
    let hookWarningsByProject: [Project.ID: String]
    let onAdd: () -> Void

    @State private var renamingID: Project.ID?
    @State private var renameDraft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ScratchRow(
                    isUnread: scratchHasUnread,
                    sessionCount: scratchSessionCount
                )
                .tag(Project.scratchID)

                Section("Projects") {
                    if store.projects.isEmpty {
                        Text("No projects yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.projects) { project in
                            ProjectRow(
                                project: project,
                                isUnread: unreadProjectIDs.contains(project.id),
                                sessionCount: sessionCountByProject[project.id] ?? 0,
                                hookWarning: hookWarningsByProject[project.id],
                                isRenaming: renamingID == project.id,
                                renameDraft: $renameDraft,
                                onRenameCommit: {
                                    commitRename(project)
                                }
                            )
                            .tag(project.id)
                            .contextMenu {
                                Button("Rename") { beginRename(project) }
                                Divider()
                                Button("Reveal in Finder") { revealInFinder(project) }
                                Button("Open in Terminal.app") { openInTerminal(project) }
                                Divider()
                                Button(role: .destructive) {
                                    store.remove(project.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)

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

    // MARK: Rename

    private func beginRename(_ project: Project) {
        renameDraft = project.name
        renamingID = project.id
    }

    private func commitRename(_ project: Project) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.rename(project.id, to: trimmed)
        }
        renamingID = nil
        renameDraft = ""
    }

    // MARK: External openers

    private func revealInFinder(_ project: Project) {
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: project.path)]
        )
    }

    private func openInTerminal(_ project: Project) {
        let url = URL(fileURLWithPath: project.path)
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

private struct ScratchRow: View {
    let isUnread: Bool
    let sessionCount: Int

    var body: some View {
        HStack(spacing: 6) {
            if isUnread {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
            }
            Image(systemName: "tray").foregroundStyle(.secondary)
            Text("Scratch").font(.body)
            Spacer()
            if sessionCount > 0 {
                CountBadge(count: sessionCount)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ProjectRow: View {
    let project: Project
    let isUnread: Bool
    let sessionCount: Int
    let hookWarning: String?
    let isRenaming: Bool
    @Binding var renameDraft: String
    let onRenameCommit: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if isUnread {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
            }
            VcsIcon(isJj: project.isJjRepo)

            VStack(alignment: .leading, spacing: 2) {
                if isRenaming {
                    TextField("Name", text: $renameDraft, onCommit: onRenameCommit)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                } else {
                    Text(project.name)
                        .font(.body)
                        .lineLimit(1)
                }
                Text(project.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if let warning = hookWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .help(warning)
            }

            if sessionCount > 0 {
                CountBadge(count: sessionCount)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct VcsIcon: View {
    let isJj: Bool

    var body: some View {
        Group {
            if isJj {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.tint)
                    .help("jj repository")
            } else {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                    .help("Plain directory")
            }
        }
        .font(.caption)
        .frame(width: 16)
    }
}

private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                Capsule().fill(Color.secondary.opacity(0.15))
            )
    }
}
