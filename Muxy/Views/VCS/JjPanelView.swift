import AppKit
import Foundation
import MuxyShared
import SwiftUI

struct JjPanelView: View {
    @Bindable var state: JjPanelState
    @State private var showDescribeSheet = false
    @State private var showCommitSheet = false
    @State private var actionError: String?
    @State private var pendingDescribeChange: JjLogEntry?
    @State private var filesCollapsed = false
    @State private var changesCollapsed = false
    @State private var bookmarksCollapsed = false
    @State private var conflictsCollapsed = false

    private let mutator = JjMutationService(queue: JjProcessQueue.shared)
    private let bookmarkService = JjBookmarkService(queue: JjProcessQueue.shared)

    @State private var showCreateBookmarkSheet = false
    @State private var pendingCreateBookmarkRevset: String?
    private static let sectionHeaderHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            actionBar
            if let actionError {
                Text(actionError)
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            if let snapshot = state.snapshot {
                VStack(alignment: .leading, spacing: 0) {
                    changeCard(snapshot: snapshot)
                    sectionLayout(snapshot: snapshot)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if let error = state.errorMessage {
                errorBanner(message: error)
            } else if state.isLoading {
                loadingBanner
            } else {
                emptyState
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await state.refresh() }
        .sheet(isPresented: $showDescribeSheet) {
            JjMessageSheet(
                title: "Describe Change",
                confirmLabel: "Save",
                onConfirm: { message in
                    showDescribeSheet = false
                    if let pendingDescribeChange {
                        let revset = pendingDescribeChange.change.prefix
                        self.pendingDescribeChange = nil
                        runMutation { try await mutator.describe(repoPath: state.repoPath, revset: revset, message: message) }
                    } else {
                        runMutation { try await mutator.describe(repoPath: state.repoPath, message: message) }
                    }
                },
                onCancel: {
                    pendingDescribeChange = nil
                    showDescribeSheet = false
                }
            )
        }
        .sheet(isPresented: $showCommitSheet) {
            JjMessageSheet(
                title: "Commit Working Copy",
                confirmLabel: "Commit",
                onConfirm: { message in
                    showCommitSheet = false
                    runMutation { try await mutator.commit(repoPath: state.repoPath, message: message) }
                },
                onCancel: { showCommitSheet = false }
            )
        }
        .sheet(isPresented: $showCreateBookmarkSheet) {
            JjBookmarkCreateSheet(
                onConfirm: { name in
                    let revset = pendingCreateBookmarkRevset ?? "@"
                    pendingCreateBookmarkRevset = nil
                    showCreateBookmarkSheet = false
                    runMutation {
                        try await bookmarkService.create(
                            repoPath: state.repoPath,
                            name: name,
                            revset: revset
                        )
                    }
                },
                onCancel: {
                    pendingCreateBookmarkRevset = nil
                    showCreateBookmarkSheet = false
                }
            )
        }
    }

    private func sectionLayout(snapshot: JjPanelSnapshot) -> some View {
        GeometryReader { geo in
            let sections = sections(for: snapshot)
            let expanded = sections.filter { !isCollapsed($0) }
            let collapsedHeight = CGFloat(sections.count - expanded.count) * Self.sectionHeaderHeight
            let dividerHeight = CGFloat(sections.count + 1)
            let availableHeight = max(0, geo.size.height - collapsedHeight - dividerHeight)
            let expandedHeight = expanded.isEmpty ? 0 : availableHeight / CGFloat(expanded.count)

            VStack(spacing: 0) {
                ForEach(sections, id: \.self) { section in
                    Rectangle().fill(MuxyTheme.border).frame(height: 1)
                    if isCollapsed(section) {
                        sectionHeader(section, count: sectionCount(section, snapshot: snapshot))
                            .frame(height: Self.sectionHeaderHeight)
                    } else {
                        VStack(spacing: 0) {
                            sectionHeader(section, count: sectionCount(section, snapshot: snapshot))
                            ScrollView {
                                sectionContent(section, snapshot: snapshot)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(height: max(Self.sectionHeaderHeight, expandedHeight))
                    }
                }
                Rectangle().fill(MuxyTheme.border).frame(height: 1)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sections(for snapshot: JjPanelSnapshot) -> [JjPanelSection] {
        var sections: [JjPanelSection] = [.files, .changes, .bookmarks]
        if !snapshot.conflicts.isEmpty {
            sections.append(.conflicts)
        }
        return sections
    }

    @ViewBuilder
    private func sectionContent(_ section: JjPanelSection, snapshot: JjPanelSnapshot) -> some View {
        switch section {
        case .files:
            fileListContent(entries: snapshot.status.entries)
        case .changes:
            changeGraphContent(entries: snapshot.changes, bookmarks: snapshot.bookmarks)
        case .bookmarks:
            bookmarkListContent(bookmarks: snapshot.bookmarks)
        case .conflicts:
            conflictListContent(conflicts: snapshot.conflicts)
        }
    }

    private func sectionCount(_ section: JjPanelSection, snapshot: JjPanelSnapshot) -> Int {
        switch section {
        case .files: snapshot.status.entries.count
        case .changes: snapshot.changes.count
        case .bookmarks: snapshot.bookmarks.count
        case .conflicts: snapshot.conflicts.count
        }
    }

    private func sectionHeader(_ section: JjPanelSection, count: Int) -> some View {
        HStack(spacing: 6) {
            Button {
                toggleSection(section)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed(section) ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(MuxyTheme.fgDim)
                        .frame(width: 10)
                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MuxyTheme.fgMuted)
                }
            }
            .buttonStyle(.plain)

            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(MuxyTheme.bg)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(MuxyTheme.fgMuted, in: Capsule())

            Spacer(minLength: 0)

            if section == .bookmarks {
                Button {
                    pendingCreateBookmarkRevset = nil
                    showCreateBookmarkSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("New bookmark")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    private func isCollapsed(_ section: JjPanelSection) -> Bool {
        switch section {
        case .files: filesCollapsed
        case .changes: changesCollapsed
        case .bookmarks: bookmarksCollapsed
        case .conflicts: conflictsCollapsed
        }
    }

    private func toggleSection(_ section: JjPanelSection) {
        switch section {
        case .files: filesCollapsed.toggle()
        case .changes: changesCollapsed.toggle()
        case .bookmarks: bookmarksCollapsed.toggle()
        case .conflicts: conflictsCollapsed.toggle()
        }
    }

    private var header: some View {
        HStack {
            Text("Changes")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                Task { await state.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(state.isLoading)
            .accessibilityLabel("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func changeCard(snapshot: JjPanelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(snapshot.show.change.prefix)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MuxyTheme.accent)
                Text(snapshot.show.change.full)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(snapshot.show.description.isEmpty ? "(no description)" : snapshot.show.description)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func fileListContent(entries: [JjStatusEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if entries.isEmpty {
                Text("No working copy changes")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgDim)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entries, id: \.path) { entry in
                        HStack(spacing: 6) {
                            Text(entry.change.rawValue)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(color(for: entry.change))
                                .frame(width: 12)
                            Text(entry.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fg)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func changeGraphContent(entries: [JjLogEntry], bookmarks: [JjBookmark]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if entries.isEmpty {
                Text("No changes")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgDim)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.change.prefix) { index, entry in
                        JjChangeRow(
                            entry: entry,
                            bookmarks: bookmarks,
                            isFirst: index == 0,
                            isLast: index == entries.count - 1,
                            onCopyChangeID: { copyToPasteboard(entry.change.prefix) },
                            onCopyCommitID: { copyToPasteboard(entry.commitId) },
                            onCopyDescription: { copyToPasteboard(entry.description) },
                            onEdit: {
                                runMutation {
                                    try await mutator.edit(
                                        repoPath: state.repoPath,
                                        revset: entry.change.prefix
                                    )
                                }
                            },
                            onDescribe: {
                                pendingDescribeChange = entry
                                showDescribeSheet = true
                            },
                            onNewAt: {
                                runMutation { try await mutator.newAt(repoPath: state.repoPath, revset: entry.change.prefix) }
                            },
                            onNewAfter: {
                                runMutation { try await mutator.newAfter(repoPath: state.repoPath, revset: entry.change.prefix) }
                            },
                            onNewBefore: {
                                runMutation { try await mutator.newBefore(repoPath: state.repoPath, revset: entry.change.prefix) }
                            },
                            onDuplicate: {
                                runMutation { try await mutator.duplicate(repoPath: state.repoPath, revset: entry.change.prefix) }
                            },
                            onSquashInto: {
                                runMutation { try await mutator.squashInto(repoPath: state.repoPath, revset: entry.change.prefix) }
                            },
                            onRebaseOnto: {
                                runMutation {
                                    try await mutator.rebaseWorkingCopyOnto(repoPath: state.repoPath, revset: entry.change.prefix)
                                }
                            },
                            onCreateBookmark: {
                                pendingCreateBookmarkRevset = entry.change.prefix
                                showCreateBookmarkSheet = true
                            },
                            onMoveBookmark: { bookmarkName in
                                runMutation {
                                    try await bookmarkService.setTarget(
                                        repoPath: state.repoPath,
                                        name: bookmarkName,
                                        revset: entry.change.prefix
                                    )
                                }
                            },
                            onAbandon: {
                                runMutation { try await mutator.abandon(repoPath: state.repoPath, revset: entry.change.prefix) }
                            },
                            onRevert: {
                                runMutation { try await mutator.revert(repoPath: state.repoPath, revset: entry.change.prefix) }
                            }
                        )
                    }
                }
            }
        }
    }

    private func color(for change: JjFileChange) -> Color {
        switch change {
        case .added,
             .copied: MuxyTheme.diffAddFg
        case .deleted: MuxyTheme.diffRemoveFg
        case .modified,
             .renamed: MuxyTheme.fgMuted
        }
    }

    private func bookmarkListContent(bookmarks: [JjBookmark]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if bookmarks.isEmpty {
                Text("No bookmarks")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgDim)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(bookmarks, id: \.name) { bookmark in
                        HStack(spacing: 6) {
                            Image(systemName: "bookmark")
                                .font(.system(size: 9))
                                .foregroundStyle(MuxyTheme.accent)
                                .frame(width: 12)
                            Text(bookmark.name)
                                .font(.system(size: 11))
                                .foregroundStyle(MuxyTheme.fg)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let target = bookmark.target {
                                Text(target.prefix)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(MuxyTheme.fgDim)
                            }
                            if !bookmark.isLocal, !bookmark.remotes.isEmpty {
                                Text("(\(bookmark.remotes.joined(separator: ",")))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(MuxyTheme.fgDim)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Move to current change") {
                                runMutation {
                                    try await bookmarkService.setTarget(
                                        repoPath: state.repoPath,
                                        name: bookmark.name,
                                        revset: "@"
                                    )
                                }
                            }
                            Button("Delete", role: .destructive) {
                                runMutation {
                                    try await bookmarkService.forget(
                                        repoPath: state.repoPath,
                                        name: bookmark.name
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func conflictListContent(conflicts: [JjConflict]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if conflicts.isEmpty {
                Text("No conflicts")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgDim)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(conflicts, id: \.path) { conflict in
                        Text(conflict.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(MuxyTheme.fg)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.diffRemoveFg)
            Spacer()
        }
        .padding(10)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
    }

    private var loadingBanner: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Loading…")
                .font(.system(size: 11))
                .foregroundStyle(MuxyTheme.fgMuted)
        }
    }

    private var emptyState: some View {
        Text("No data")
            .font(.system(size: 11))
            .foregroundStyle(MuxyTheme.fgDim)
    }

    private var actionBar: some View {
        JjActionBar(
            onDescribe: { showDescribeSheet = true },
            onNew: { runMutation { try await mutator.newChange(repoPath: state.repoPath) } },
            onCommit: { showCommitSheet = true },
            onSquash: { runMutation { try await mutator.squash(repoPath: state.repoPath) } },
            onAbandon: { runMutation { try await mutator.abandon(repoPath: state.repoPath) } },
            onDuplicate: { runMutation { try await mutator.duplicate(repoPath: state.repoPath) } },
            onRevert: { runMutation { try await mutator.revert(repoPath: state.repoPath) } }
        )
    }

    private func runMutation(_ work: @escaping () async throws -> Void) {
        Task {
            do {
                try await work()
                actionError = nil
                await state.refresh()
            } catch {
                actionError = String(describing: error)
            }
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

private enum JjPanelSection: CaseIterable {
    case files
    case changes
    case bookmarks
    case conflicts

    var title: String {
        switch self {
        case .files: "Files"
        case .changes: "Changes"
        case .bookmarks: "Bookmarks"
        case .conflicts: "Conflicts"
        }
    }
}

private struct JjChangeRow: View {
    let entry: JjLogEntry
    let bookmarks: [JjBookmark]
    let isFirst: Bool
    let isLast: Bool
    let onCopyChangeID: () -> Void
    let onCopyCommitID: () -> Void
    let onCopyDescription: () -> Void
    let onEdit: () -> Void
    let onDescribe: () -> Void
    let onNewAt: () -> Void
    let onNewAfter: () -> Void
    let onNewBefore: () -> Void
    let onDuplicate: () -> Void
    let onSquashInto: () -> Void
    let onRebaseOnto: () -> Void
    let onCreateBookmark: () -> Void
    let onMoveBookmark: (String) -> Void
    let onAbandon: () -> Void
    let onRevert: () -> Void
    @State private var hovered = false

    private var isCurrent: Bool {
        entry.graphPrefix.contains("@")
    }

    private var title: String {
        if !entry.description.isEmpty { return entry.description }
        return entry.isEmpty ? "(empty)" : "(no description)"
    }

    private var localBookmarks: [JjBookmark] {
        bookmarks.filter { $0.isLocal }
    }

    private var targetBookmarks: [JjBookmark] {
        bookmarks.filter { bookmark in
            guard let target = bookmark.target else { return false }
            return target.full == entry.change.full || target.prefix == entry.change.prefix
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            graphRail

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(entry.isEmpty ? MuxyTheme.fgMuted : MuxyTheme.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    if isCurrent {
                        Text("@")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(MuxyTheme.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(MuxyTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                    }
                    Text(entry.change.prefix)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(MuxyTheme.accent)
                    Text(entry.authorName)
                        .font(.system(size: 10))
                        .foregroundStyle(MuxyTheme.fgDim)
                        .lineLimit(1)
                    Text(relativeDate(entry.authorTimestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(MuxyTheme.fgDim)
                    ForEach(targetBookmarks, id: \.name) { bookmark in
                        JjBookmarkBadge(bookmark: bookmark)
                    }
                }
            }

            Spacer(minLength: 0)

            if hovered {
                Text(entry.commitId)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(hovered ? MuxyTheme.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Copy Change ID", action: onCopyChangeID)
            Button("Copy Commit ID", action: onCopyCommitID)
            Button("Copy Description", action: onCopyDescription)
                .disabled(entry.description.isEmpty)

            Divider()

            Button("Edit Change", action: onEdit)
            Button("Describe Change...", action: onDescribe)

            Divider()

            Button("New After", action: onNewAfter)
            Button("New Change Here", action: onNewAt)
            Button("New Before", action: onNewBefore)
            Button("Duplicate Change", action: onDuplicate)

            Divider()

            Button("Squash @ Into This Change", action: onSquashInto)
            Button("Rebase @ Onto This Change", action: onRebaseOnto)

            Divider()

            Button("Create Bookmark Here...", action: onCreateBookmark)
            Menu("Move Bookmark Here") {
                if localBookmarks.isEmpty {
                    Text("No local bookmarks")
                } else {
                    ForEach(localBookmarks, id: \.name) { bookmark in
                        Button(bookmark.name) {
                            onMoveBookmark(bookmark.name)
                        }
                    }
                }
            }
            .disabled(localBookmarks.isEmpty)

            Divider()

            Button("Revert Change", action: onRevert)
            Button("Abandon Change", role: .destructive, action: onAbandon)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(entry.change.prefix), \(entry.authorName), \(relativeDate(entry.authorTimestamp))")
    }

    private var graphRail: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(isFirst ? .clear : MuxyTheme.fgDim.opacity(0.35))
                Rectangle()
                    .fill(isLast ? .clear : MuxyTheme.fgDim.opacity(0.35))
            }
            .frame(width: 1)

            Circle()
                .fill(isCurrent ? MuxyTheme.accent : MuxyTheme.fgDim)
                .frame(width: 8, height: 8)
        }
        .frame(width: 12, height: 40)
    }
}

private struct JjBookmarkBadge: View {
    let bookmark: JjBookmark

    private var label: String {
        if bookmark.isLocal {
            return bookmark.name
        }
        if let remote = bookmark.remotes.first {
            return "\(remote)/\(bookmark.name)"
        }
        return bookmark.name
    }

    private var foreground: Color {
        bookmark.isLocal ? MuxyTheme.accent : MuxyTheme.fgMuted
    }

    private var background: Color {
        bookmark.isLocal ? MuxyTheme.accent.opacity(0.12) : MuxyTheme.surface
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 7))
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(background, in: RoundedRectangle(cornerRadius: 3))
    }
}

private func relativeDate(_ isoString: String) -> String {
    let formatter = ISO8601DateFormatter()
    let date = formatter.date(from: isoString) ?? Date()
    let interval = Date().timeIntervalSince(date)

    guard interval > 0 else { return "just now" }

    let minute: TimeInterval = 60
    let hour: TimeInterval = 3600
    let day: TimeInterval = 86400
    let week: TimeInterval = 604_800
    let month: TimeInterval = 2_592_000
    let year: TimeInterval = 31_536_000

    if interval < minute {
        return "just now"
    } else if interval < hour {
        return "\(Int(interval / minute))m ago"
    } else if interval < day {
        return "\(Int(interval / hour))h ago"
    } else if interval < week {
        return "\(Int(interval / day))d ago"
    } else if interval < month {
        return "\(Int(interval / week))w ago"
    } else if interval < year {
        return "\(Int(interval / month))mo ago"
    } else {
        return "\(Int(interval / year))y ago"
    }
}
