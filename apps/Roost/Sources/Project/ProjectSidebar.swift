import SwiftUI

struct ProjectSidebar: View {
    @ObservedObject var store: ProjectStore
    @Binding var selection: Project.ID?
    let sessions: [LaunchedSession]
    @Binding var selectedSessionID: LaunchedSession.ID?
    let unreadProjectIDs: Set<Project.ID>
    let unreadSessions: Set<LaunchedSession.ID>
    let scratchHasUnread: Bool
    let scratchSessionCount: Int
    let sessionCountByProject: [Project.ID: Int]
    /// M5: latest setup/teardown hook failure per project, keyed by ID.
    /// Shown as a ⚠ icon with a tooltip on the project row.
    let hookWarningsByProject: [Project.ID: String]
    let onAdd: () -> Void
    let onSelectSession: (LaunchedSession.ID, Project.ID?) -> Void
    let onCloseSession: (LaunchedSession.ID) -> Void

    @State private var renamingID: Project.ID?
    @State private var renameDraft: String = ""
    /// Per-bucket expansion. Default unset → expanded (so new users see
    /// tabs without having to flip chevrons).
    @State private var collapsed: Set<Project.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ScratchBucket(
                    isExpanded: !collapsed.contains(Project.scratchID),
                    hasUnread: scratchHasUnread,
                    sessionCount: scratchSessionCount,
                    sessions: sessions.filter { $0.projectID == nil },
                    selectedSessionID: selectedSessionID,
                    unreadSessions: unreadSessions,
                    onToggle: { toggleCollapsed(Project.scratchID) },
                    onSelectSession: { onSelectSession($0, nil) },
                    onCloseSession: onCloseSession
                )
                .tag(Project.scratchID)

                Section("Projects") {
                    if store.projects.isEmpty {
                        Text("No projects yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.projects) { project in
                            ProjectBucket(
                                project: project,
                                isExpanded: !collapsed.contains(project.id),
                                isUnread: unreadProjectIDs.contains(project.id),
                                sessionCount: sessionCountByProject[project.id] ?? 0,
                                hookWarning: hookWarningsByProject[project.id],
                                isRenaming: renamingID == project.id,
                                renameDraft: $renameDraft,
                                sessions: sessions.filter { $0.projectID == project.id },
                                selectedSessionID: selectedSessionID,
                                unreadSessions: unreadSessions,
                                onToggle: { toggleCollapsed(project.id) },
                                onRenameCommit: { commitRename(project) },
                                onSelectSession: { onSelectSession($0, project.id) },
                                onCloseSession: onCloseSession
                            )
                            .tag(project.id)
                            .contextMenu {
                                Button("Rename") { beginRename(project) }
                                Divider()
                                Button("Reveal in Finder") { revealInFinder(project) }
                                openInTerminalMenu(for: project.path)
                                openInIDEMenu(for: project.path)
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

    private func toggleCollapsed(_ id: Project.ID) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
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

    /// Context-menu sub-menu listing every IDE LaunchServices says is
    /// installed. Empty list → a disabled placeholder so users still see
    /// why nothing's available.
    @ViewBuilder
    private func openInIDEMenu(for path: String) -> some View {
        let installed = IDEOpener.installed()
        Menu("Open in IDE") {
            if installed.isEmpty {
                Text("No supported editors detected")
            } else {
                ForEach(installed, id: \.0.bundleID) { pair in
                    Button(pair.0.name) {
                        IDEOpener.open(directory: path, with: pair.1)
                    }
                }
            }
        }
    }

    /// Sibling of `openInIDEMenu`: lists installed terminal emulators
    /// (Ghostty / iTerm / WezTerm / Alacritty / Kitty / Warp / Hyper /
    /// Terminal.app).
    @ViewBuilder
    private func openInTerminalMenu(for path: String) -> some View {
        let installed = TerminalOpener.installed()
        Menu("Open in Terminal") {
            if installed.isEmpty {
                Text("No supported terminals detected")
            } else {
                ForEach(installed, id: \.0.bundleID) { pair in
                    Button(pair.0.name) {
                        TerminalOpener.open(directory: path, with: pair.1)
                    }
                }
            }
        }
    }
}

// MARK: - Bucket rows (DisclosureGroup-style)

private struct ScratchBucket: View {
    let isExpanded: Bool
    let hasUnread: Bool
    let sessionCount: Int
    let sessions: [LaunchedSession]
    let selectedSessionID: LaunchedSession.ID?
    let unreadSessions: Set<LaunchedSession.ID>
    let onToggle: () -> Void
    let onSelectSession: (LaunchedSession.ID) -> Void
    let onCloseSession: (LaunchedSession.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                if hasUnread {
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

            if isExpanded && !sessions.isEmpty {
                SessionChildren(
                    sessions: sessions,
                    selectedSessionID: selectedSessionID,
                    unreadSessions: unreadSessions,
                    onSelectSession: onSelectSession,
                    onCloseSession: onCloseSession
                )
            }
        }
    }
}

private struct ProjectBucket: View {
    let project: Project
    let isExpanded: Bool
    let isUnread: Bool
    let sessionCount: Int
    let hookWarning: String?
    let isRenaming: Bool
    @Binding var renameDraft: String
    let sessions: [LaunchedSession]
    let selectedSessionID: LaunchedSession.ID?
    let unreadSessions: Set<LaunchedSession.ID>
    let onToggle: () -> Void
    let onRenameCommit: () -> Void
    let onSelectSession: (LaunchedSession.ID) -> Void
    let onCloseSession: (LaunchedSession.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
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

            if isExpanded && !sessions.isEmpty {
                SessionChildren(
                    sessions: sessions,
                    selectedSessionID: selectedSessionID,
                    unreadSessions: unreadSessions,
                    onSelectSession: onSelectSession,
                    onCloseSession: onCloseSession
                )
            }
        }
    }
}

private struct SessionChildren: View {
    let sessions: [LaunchedSession]
    let selectedSessionID: LaunchedSession.ID?
    let unreadSessions: Set<LaunchedSession.ID>
    let onSelectSession: (LaunchedSession.ID) -> Void
    let onCloseSession: (LaunchedSession.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(sessions) { s in
                SessionRow(
                    session: s,
                    isSelected: s.id == selectedSessionID,
                    isUnread: unreadSessions.contains(s.id),
                    onSelect: { onSelectSession(s.id) },
                    onClose: { onCloseSession(s.id) }
                )
            }
        }
        .padding(.leading, 20)
    }
}

private struct SessionRow: View {
    let session: LaunchedSession
    let isSelected: Bool
    let isUnread: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    /// cwd for "Reveal" / "Open in …" menu items. Empty for sessions whose
    /// spec left it blank (rare; agent CLI without workspace).
    private var cwd: String? {
        let d = session.spec.workingDirectory
        return d.isEmpty ? nil : d
    }

    var body: some View {
        HStack(spacing: 6) {
            if isUnread {
                Circle().fill(Color.blue).frame(width: 5, height: 5)
            } else {
                // Reserve space so text columns align whether unread or not.
                Color.clear.frame(width: 5, height: 5)
            }
            Image(systemName: agentIcon)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(width: 14)
            Button(action: onSelect) {
                Text(session.label)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close session")
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
        .contextMenu {
            if let cwd = cwd {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: cwd)]
                    )
                }
                let terminals = TerminalOpener.installed()
                Menu("Open in Terminal") {
                    if terminals.isEmpty {
                        Text("No supported terminals detected")
                    } else {
                        ForEach(terminals, id: \.0.bundleID) { pair in
                            Button(pair.0.name) {
                                TerminalOpener.open(directory: cwd, with: pair.1)
                            }
                        }
                    }
                }
                let ides = IDEOpener.installed()
                Menu("Open in IDE") {
                    if ides.isEmpty {
                        Text("No supported editors detected")
                    } else {
                        ForEach(ides, id: \.0.bundleID) { pair in
                            Button(pair.0.name) {
                                IDEOpener.open(directory: cwd, with: pair.1)
                            }
                        }
                    }
                }
                Divider()
            }
            Button(role: .destructive, action: onClose) {
                Label("Close", systemImage: "xmark.circle")
            }
        }
    }

    private var agentIcon: String {
        let lowered = session.spec.agentKind.lowercased()
        switch lowered {
        case "shell": return "terminal"
        case "claude": return "sparkle"
        case "codex": return "chevron.left.forwardslash.chevron.right"
        case "gemini": return "diamond"
        default: return "play.rectangle"
        }
    }
}

// MARK: - Supporting views

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
