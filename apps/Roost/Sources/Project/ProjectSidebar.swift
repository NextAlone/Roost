import SwiftUI
import UniformTypeIdentifiers

/// Sidebar rewrite: `ScrollView + LazyVStack` instead of `List` + hand-rolled
/// `DisclosureGroup`s. The List sidebar style was forcing a full re-layout +
/// implicit animation on every `selection` binding change, which made rapid
/// project switching stall the main thread.
///
/// Single pass of grouping happens in `buckets`, then each `BucketRow` is
/// `Equatable` so SwiftUI skips diffing when its inputs didn't change.
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
    let hookWarningsByProject: [Project.ID: String]
    let onAdd: () -> Void
    let onSelectSession: (LaunchedSession.ID, Project.ID?) -> Void
    let onCloseSession: (LaunchedSession.ID) -> Void

    @State private var collapsed: Set<Project.ID> = []
    @State private var renamingID: Project.ID?
    @State private var renameDraft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    // Scratch area
                    bucketRow(for: scratchBucket)
                        .padding(.bottom, 4)

                    SectionHeader(title: "Projects")

                    ForEach(projectBuckets) { bucket in
                        bucketRow(for: bucket)
                            .onDrag({
                                NSItemProvider(
                                    object: bucket.id.uuidString as NSString
                                )
                            }, preview: {
                                DragPreview(label: bucket.name)
                            })
                            .onDrop(
                                of: [.plainText],
                                delegate: ProjectDropDelegate(
                                    store: store,
                                    target: .before(bucket.id)
                                )
                            )
                    }

                    // Tail drop zone: lets the user drop a project at the
                    // very bottom of the list (targets don't exist below
                    // the last row). Invisible; grows enough to catch a
                    // reasonable drop.
                    Color.clear
                        .frame(height: 40)
                        .contentShape(Rectangle())
                        .onDrop(
                            of: [.plainText],
                            delegate: ProjectDropDelegate(
                                store: store,
                                target: .end
                            )
                        )
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
            }

            Divider()
            AddButton(onAdd: onAdd)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Projects")
    }

    @ViewBuilder
    private func bucketRow(for bucket: SidebarBucket) -> some View {
        BucketRow(
            bucket: bucket,
            isCollapsed: collapsed.contains(bucket.id),
            isSelected: selection == bucket.id,
            selectedSessionID: selectedSessionID,
            unreadSessions: unreadSessions,
            isRenaming: renamingID == bucket.id,
            renameDraft: $renameDraft,
            onToggle: { toggleCollapsed(bucket.id) },
            onSelectBucket: { selection = bucket.id },
            onSelectSession: { sid in
                onSelectSession(sid, bucket.isScratch ? nil : bucket.id)
            },
            onCloseSession: onCloseSession,
            onRenameBegin: { beginRename(bucket.id) },
            onRenameCommit: { commitRename(bucket.id) },
            onRevealProject: { revealInFinder(bucket.path) },
            onRemoveProject: { store.remove(bucket.id) }
        )
    }

    // MARK: One-shot bucket grouping

    private var grouped: [Project.ID?: [LaunchedSession]] {
        Dictionary(grouping: sessions) { $0.projectID }
    }

    private var scratchBucket: SidebarBucket {
        SidebarBucket(
            id: Project.scratchID,
            name: "Scratch",
            path: nil,
            isJj: false,
            isScratch: true,
            sessions: grouped[nil] ?? [],
            hookWarning: nil,
            hasUnread: scratchHasUnread,
            sessionCount: scratchSessionCount
        )
    }

    private var projectBuckets: [SidebarBucket] {
        let g = grouped
        return store.projects.map { p in
            SidebarBucket(
                id: p.id,
                name: p.name,
                path: p.path,
                isJj: p.isJjRepo,
                isScratch: false,
                sessions: g[p.id] ?? [],
                hookWarning: hookWarningsByProject[p.id],
                hasUnread: unreadProjectIDs.contains(p.id),
                sessionCount: sessionCountByProject[p.id] ?? 0
            )
        }
    }

    // MARK: Helpers

    private func toggleCollapsed(_ id: Project.ID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    private func beginRename(_ id: Project.ID) {
        guard let p = store.projects.first(where: { $0.id == id }) else { return }
        renameDraft = p.name
        renamingID = id
    }

    private func commitRename(_ id: Project.ID) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { store.rename(id, to: trimmed) }
        renamingID = nil
        renameDraft = ""
    }

    private func revealInFinder(_ path: String?) {
        guard let path = path else { return }
        NSWorkspace.shared.activateFileViewerSelecting(
            [URL(fileURLWithPath: path)]
        )
    }
}

// MARK: - Bucket row (equatable: skips render when unchanged)

struct SidebarBucket: Identifiable, Equatable {
    let id: Project.ID
    let name: String
    let path: String?
    let isJj: Bool
    let isScratch: Bool
    let sessions: [LaunchedSession]
    let hookWarning: String?
    let hasUnread: Bool
    let sessionCount: Int
}

private struct BucketRow: View, Equatable {
    let bucket: SidebarBucket
    let isCollapsed: Bool
    let isSelected: Bool
    let selectedSessionID: LaunchedSession.ID?
    let unreadSessions: Set<LaunchedSession.ID>
    let isRenaming: Bool
    @Binding var renameDraft: String
    let onToggle: () -> Void
    let onSelectBucket: () -> Void
    let onSelectSession: (LaunchedSession.ID) -> Void
    let onCloseSession: (LaunchedSession.ID) -> Void
    let onRenameBegin: () -> Void
    let onRenameCommit: () -> Void
    let onRevealProject: () -> Void
    let onRemoveProject: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bucket == rhs.bucket
            && lhs.isCollapsed == rhs.isCollapsed
            && lhs.isSelected == rhs.isSelected
            && lhs.selectedSessionID == rhs.selectedSessionID
            && lhs.isRenaming == rhs.isRenaming
            // unreadSessions: set equality short-circuits when the same reference
            && lhs.unreadSessions == rhs.unreadSessions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            if !isCollapsed && !bucket.sessions.isEmpty {
                ForEach(bucket.sessions) { s in
                    SessionChild(
                        session: s,
                        isSelected: s.id == selectedSessionID,
                        isUnread: unreadSessions.contains(s.id),
                        onSelect: { onSelectSession(s.id) },
                        onClose: { onCloseSession(s.id) }
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            // Larger tap surface — the raw chevron glyph at 12pt was hard
            // to hit precisely.
            Button(action: onToggle) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if bucket.hasUnread {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
            }

            Image(systemName: leadingIcon)
                .font(.caption)
                .foregroundStyle(leadingIconTint)
                .frame(width: 16)

            if isRenaming && !bucket.isScratch {
                TextField("Name", text: $renameDraft, onCommit: onRenameCommit)
                    .textFieldStyle(.roundedBorder)
                    .font(.body)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(bucket.name)
                        .font(.body)
                        .lineLimit(1)
                    if let path = bucket.path {
                        Text(path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            Spacer()

            if let warning = bucket.hookWarning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .help(warning)
            }
            if bucket.sessionCount > 0 {
                CountBadge(count: bucket.sessionCount)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelectBucket() }
        .contextMenu {
            if !bucket.isScratch {
                Button("Rename") { onRenameBegin() }
                Divider()
            }
            if let path = bucket.path {
                Button("Reveal in Finder") { onRevealProject() }
                openInTerminalMenu(for: path)
                openInIDEMenu(for: path)
            }
            if !bucket.isScratch {
                Divider()
                Button(role: .destructive) { onRemoveProject() } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    private var leadingIcon: String {
        if bucket.isScratch { return "tray" }
        return bucket.isJj ? "point.3.connected.trianglepath.dotted" : "folder"
    }

    private var leadingIconTint: Color {
        if bucket.isScratch { return .secondary }
        return bucket.isJj ? .accentColor : .secondary
    }

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
}

// MARK: - Session child

private struct SessionChild: View, Equatable {
    let session: LaunchedSession
    let isSelected: Bool
    let isUnread: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session == rhs.session
            && lhs.isSelected == rhs.isSelected
            && lhs.isUnread == rhs.isUnread
    }

    private var cwd: String? {
        let d = session.spec.workingDirectory
        return d.isEmpty ? nil : d
    }

    var body: some View {
        HStack(spacing: 6) {
            if isUnread {
                Circle().fill(Color.blue).frame(width: 5, height: 5)
            } else {
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
        .padding(.vertical, 2)
        .padding(.leading, 28)
        .padding(.trailing, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            if let cwd = cwd {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [URL(fileURLWithPath: cwd)]
                    )
                }
                sessionTerminalMenu(cwd: cwd)
                sessionIDEMenu(cwd: cwd)
                Divider()
            }
            Button(role: .destructive, action: onClose) {
                Label("Close", systemImage: "xmark.circle")
            }
        }
    }

    private var agentIcon: String {
        switch session.spec.agentKind.lowercased() {
        case "shell":  return "terminal"
        case "claude": return "sparkle"
        case "codex":  return "chevron.left.forwardslash.chevron.right"
        case "gemini": return "diamond"
        default:       return "play.rectangle"
        }
    }

    @ViewBuilder
    private func sessionTerminalMenu(cwd: String) -> some View {
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
    }

    @ViewBuilder
    private func sessionIDEMenu(cwd: String) -> some View {
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
    }
}

// MARK: - Section header

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Fixed bottom bar

private struct AddButton: View {
    let onAdd: () -> Void
    var body: some View {
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
}

private struct CountBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)")
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }
}

// MARK: - Drag preview & drop

private struct DragPreview: View {
    let label: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.tint)
            Text(label).font(.body)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(radius: 2)
        )
    }
}

enum DropTarget {
    case before(Project.ID)
    case end
}

private struct ProjectDropDelegate: DropDelegate {
    let store: ProjectStore
    let target: DropTarget

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.plainText]).first
        else { return false }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String, let srcID = UUID(uuidString: s)
            else { return }
            DispatchQueue.main.async {
                switch target {
                case .before(let id): store.move(srcID, before: id)
                case .end:            store.moveToEnd(srcID)
                }
            }
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

