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
    @State private var bookmarksCollapsed = true
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
                let graphColumnWidth = graphColumnWidth(entries: entries)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.change.prefix) { index, entry in
                        VStack(alignment: .leading, spacing: 0) {
                            JjChangeRow(
                                entry: entry,
                                bookmarks: bookmarks,
                                graphColumnWidth: graphColumnWidth,
                                previousGraphLine: index > 0 ? entries[index - 1].graphLinesAfter.last : nil,
                                nextGraphLine: entry.graphLinesAfter.first,
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
    }

    private func graphColumnWidth(entries: [JjLogEntry]) -> CGFloat {
        let graphLines = entries.flatMap { [$0.graphPrefix] + $0.graphLinesAfter }
        let maxCharacterCount = graphLines.map(\.count).max() ?? 2
        return max(18, CGFloat(maxCharacterCount) * JjGraphMetrics.characterWidth)
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
    let graphColumnWidth: CGFloat
    let previousGraphLine: String?
    let nextGraphLine: String?
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
            JjGraphView(
                graph: entry.graphPrefix,
                height: 40,
                isCurrent: isCurrent,
                previousGraphLine: previousGraphLine,
                nextGraphLine: nextGraphLine
            )
            .frame(width: graphColumnWidth, height: 40, alignment: .leading)

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
}

private enum JjGraphMetrics {
    static let characterWidth: CGFloat = 9
    static let lineWidth: CGFloat = 1
    static let nodeSize: CGFloat = 7
    static let nodeStroke: CGFloat = 1.2
    static let transitionInset: CGFloat = 4
    static let cornerRadius: CGFloat = 4
}

private struct JjGraphView: View {
    let graph: String
    let height: CGFloat
    let isCurrent: Bool
    let previousGraphLine: String?
    let nextGraphLine: String?

    private var characters: [Character] {
        Array(graph)
    }

    private var node: (index: Int, character: Character)? {
        guard let index = characters.firstIndex(where: { character in
            character == "@" || character == "○" || character == "◆"
        })
        else { return nil }
        return (index, characters[index])
    }

    var body: some View {
        ZStack(alignment: .leading) {
            graphPath
                .stroke(
                    MuxyTheme.fgDim.opacity(0.62),
                    style: StrokeStyle(
                        lineWidth: JjGraphMetrics.lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

            if let node {
                nodeElement(node.character, at: node.index)
            }

            fallbackGraphText
        }
        .frame(height: height)
    }

    @ViewBuilder
    private var fallbackGraphText: some View {
        ForEach(Array(characters.enumerated()), id: \.offset) { index, character in
            if character == "~" {
                Text(String(character))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .frame(width: JjGraphMetrics.characterWidth)
                    .position(x: xPosition(for: index), y: height / 2)
            }
        }
        ForEach(Array((nextGraphLine ?? "").enumerated()), id: \.offset) { index, character in
            if character == "~" {
                Text(String(character))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .frame(width: JjGraphMetrics.characterWidth)
                    .position(x: xPosition(for: index), y: transitionY)
            }
        }
    }

    private var graphPath: Path {
        Path { path in
            drawCurrentGraph(in: &path)
            drawNodeLines(in: &path)
            drawTransitionGraph(in: &path)
        }
    }

    private var centerY: CGFloat {
        height / 2
    }

    private var transitionY: CGFloat {
        max(centerY, height - JjGraphMetrics.transitionInset)
    }

    private var halfCharacterWidth: CGFloat {
        JjGraphMetrics.characterWidth / 2
    }

    private func drawCurrentGraph(in path: inout Path) {
        for (index, character) in characters.enumerated() {
            switch character {
            case "│":
                let nextCharacter = graphCharacter(nextGraphLine, at: index)
                drawVertical(in: &path, at: index, from: 0, to: currentVerticalEnd(nextCharacter))
            case "├":
                drawJunctionRight(in: &path, at: index, y: centerY, verticalStart: 0, verticalEnd: height)
            case "┤":
                drawJunctionLeft(in: &path, at: index, y: centerY, verticalStart: 0, verticalEnd: height)
            case "┼":
                drawJunctionCross(in: &path, at: index, y: centerY, verticalStart: 0, verticalEnd: height)
            case "┬":
                drawJunctionDown(in: &path, at: index, y: centerY, verticalEnd: height)
            case "┴":
                drawJunctionUp(in: &path, at: index, y: centerY, verticalStart: 0)
            case "─":
                drawHorizontal(
                    in: &path,
                    from: xPosition(for: index) - halfCharacterWidth,
                    to: xPosition(for: index) + halfCharacterWidth,
                    y: centerY
                )
            case "╭":
                drawCornerRightDown(in: &path, at: index, y: centerY, verticalEnd: height)
            case "╰":
                drawCornerRightUp(in: &path, at: index, y: centerY, verticalStart: 0)
            case "╮":
                drawCornerLeftDown(in: &path, at: index, y: centerY, verticalEnd: height)
            case "╯":
                drawCornerLeftUp(in: &path, at: index, y: centerY, verticalStart: 0)
            default:
                break
            }
        }
    }

    private func drawNodeLines(in path: inout Path) {
        guard let node else { return }
        if let character = graphCharacter(previousGraphLine, at: node.index),
           connectsToRowBelow(character)
        {
            drawVertical(in: &path, at: node.index, from: 0, to: centerY)
        }
        if let character = graphCharacter(nextGraphLine, at: node.index),
           connectsFromRowAbove(character)
        {
            if !closesAtTransition(character) {
                drawVertical(in: &path, at: node.index, from: centerY, to: height)
            }
        }
    }

    private func currentVerticalEnd(_ nextCharacter: Character?) -> CGFloat {
        guard let nextCharacter, closesAtTransition(nextCharacter) else { return height }
        return centerY
    }

    private func drawTransitionGraph(in path: inout Path) {
        guard let nextGraphLine else { return }
        let nextCharacters = Array(nextGraphLine)
        for (index, character) in nextCharacters.enumerated() {
            switch character {
            case "│":
                drawVertical(in: &path, at: index, from: transitionY, to: height)
            case "├":
                if rightSideClosesFromAbove(nextCharacters, after: index) {
                    drawJunctionRightFromBelow(in: &path, at: index, y: transitionY, verticalStart: centerY, verticalEnd: height)
                } else {
                    drawJunctionRight(in: &path, at: index, y: transitionY, verticalStart: centerY, verticalEnd: height)
                }
            case "┤":
                drawJunctionLeft(in: &path, at: index, y: transitionY, verticalStart: centerY, verticalEnd: height)
            case "┼":
                drawJunctionCross(in: &path, at: index, y: transitionY, verticalStart: centerY, verticalEnd: height)
            case "┬":
                drawJunctionDown(in: &path, at: index, y: transitionY, verticalEnd: height)
            case "┴":
                drawJunctionUp(in: &path, at: index, y: transitionY, verticalStart: centerY)
            case "─":
                drawHorizontal(
                    in: &path,
                    from: xPosition(for: index) - halfCharacterWidth,
                    to: xPosition(for: index) + halfCharacterWidth,
                    y: transitionY
                )
            case "╭":
                drawCornerRightDown(in: &path, at: index, y: transitionY, verticalEnd: height)
            case "╮":
                drawCornerLeftDown(in: &path, at: index, y: transitionY, verticalEnd: height)
            case "╰":
                drawCornerRightUp(in: &path, at: index, y: transitionY, verticalStart: centerY)
            case "╯":
                drawCornerLeftUp(in: &path, at: index, y: transitionY, verticalStart: centerY)
            case "╲":
                drawHorizontal(in: &path, from: xPosition(for: index), to: xPosition(for: index) + halfCharacterWidth, y: transitionY)
            case "╱":
                drawHorizontal(in: &path, from: xPosition(for: index) - halfCharacterWidth, to: xPosition(for: index), y: transitionY)
            case "╳":
                drawHorizontal(
                    in: &path,
                    from: xPosition(for: index) - halfCharacterWidth,
                    to: xPosition(for: index) + halfCharacterWidth,
                    y: transitionY
                )
            default:
                break
            }
        }
    }

    private func drawVertical(in path: inout Path, at index: Int, from start: CGFloat, to end: CGFloat) {
        drawLine(
            in: &path,
            from: CGPoint(x: xPosition(for: index), y: start),
            to: CGPoint(x: xPosition(for: index), y: end)
        )
    }

    private func drawHorizontal(in path: inout Path, from start: CGFloat, to end: CGFloat, y: CGFloat) {
        drawLine(in: &path, from: CGPoint(x: start, y: y), to: CGPoint(x: end, y: y))
    }

    private func drawJunctionRight(in path: inout Path, at index: Int, y: CGFloat, verticalStart: CGFloat, verticalEnd: CGFloat) {
        let x = xPosition(for: index)
        let radius = cornerRadius
        drawVertical(in: &path, at: index, from: verticalStart, to: verticalEnd)
        drawHorizontal(in: &path, from: x + radius, to: x + halfCharacterWidth, y: y)
        drawCurve(in: &path, from: CGPoint(x: x, y: y - radius), to: CGPoint(x: x + radius, y: y), control: CGPoint(x: x, y: y))
    }

    private func drawJunctionRightFromBelow(in path: inout Path, at index: Int, y: CGFloat, verticalStart: CGFloat, verticalEnd: CGFloat) {
        let x = xPosition(for: index)
        let radius = cornerRadius
        drawVertical(in: &path, at: index, from: verticalStart, to: verticalEnd)
        drawHorizontal(in: &path, from: x + radius, to: x + halfCharacterWidth, y: y)
        drawCurve(in: &path, from: CGPoint(x: x, y: y + radius), to: CGPoint(x: x + radius, y: y), control: CGPoint(x: x, y: y))
    }

    private func drawJunctionLeft(in path: inout Path, at index: Int, y: CGFloat, verticalStart: CGFloat, verticalEnd: CGFloat) {
        let x = xPosition(for: index)
        let radius = cornerRadius
        drawVertical(in: &path, at: index, from: verticalStart, to: verticalEnd)
        drawHorizontal(in: &path, from: x - halfCharacterWidth, to: x - radius, y: y)
        drawCurve(in: &path, from: CGPoint(x: x, y: y - radius), to: CGPoint(x: x - radius, y: y), control: CGPoint(x: x, y: y))
    }

    private func drawJunctionCross(in path: inout Path, at index: Int, y: CGFloat, verticalStart: CGFloat, verticalEnd: CGFloat) {
        let x = xPosition(for: index)
        let radius = cornerRadius
        drawVertical(in: &path, at: index, from: verticalStart, to: verticalEnd)
        drawHorizontal(in: &path, from: x - halfCharacterWidth, to: x - radius, y: y)
        drawHorizontal(in: &path, from: x + radius, to: x + halfCharacterWidth, y: y)
        drawCurve(in: &path, from: CGPoint(x: x, y: y - radius), to: CGPoint(x: x + radius, y: y), control: CGPoint(x: x, y: y))
        drawCurve(in: &path, from: CGPoint(x: x, y: y - radius), to: CGPoint(x: x - radius, y: y), control: CGPoint(x: x, y: y))
    }

    private func drawJunctionDown(in path: inout Path, at index: Int, y: CGFloat, verticalEnd: CGFloat) {
        let x = xPosition(for: index)
        let radius = cornerRadius
        drawHorizontal(in: &path, from: x - halfCharacterWidth, to: x - radius, y: y)
        drawHorizontal(in: &path, from: x + radius, to: x + halfCharacterWidth, y: y)
        drawVertical(in: &path, at: index, from: y + radius, to: verticalEnd)
        drawCurve(in: &path, from: CGPoint(x: x - radius, y: y), to: CGPoint(x: x, y: y + radius), control: CGPoint(x: x, y: y))
        drawCurve(in: &path, from: CGPoint(x: x + radius, y: y), to: CGPoint(x: x, y: y + radius), control: CGPoint(x: x, y: y))
    }

    private func drawJunctionUp(in path: inout Path, at index: Int, y: CGFloat, verticalStart: CGFloat) {
        let x = xPosition(for: index)
        let radius = cornerRadius
        drawHorizontal(in: &path, from: x - halfCharacterWidth, to: x - radius, y: y)
        drawHorizontal(in: &path, from: x + radius, to: x + halfCharacterWidth, y: y)
        drawVertical(in: &path, at: index, from: verticalStart, to: y - radius)
        drawCurve(in: &path, from: CGPoint(x: x - radius, y: y), to: CGPoint(x: x, y: y - radius), control: CGPoint(x: x, y: y))
        drawCurve(in: &path, from: CGPoint(x: x + radius, y: y), to: CGPoint(x: x, y: y - radius), control: CGPoint(x: x, y: y))
    }

    private func drawCornerRightDown(in path: inout Path, at index: Int, y: CGFloat, verticalEnd: CGFloat) {
        let x = xPosition(for: index)
        let radius = cornerRadius
        drawVertical(in: &path, at: index, from: y + radius, to: verticalEnd)
        drawHorizontal(in: &path, from: x + radius, to: x + halfCharacterWidth, y: y)
        drawCurve(in: &path, from: CGPoint(x: x, y: y + radius), to: CGPoint(x: x + radius, y: y), control: CGPoint(x: x, y: y))
    }

    private func drawCornerRightUp(in path: inout Path, at index: Int, y: CGFloat, verticalStart: CGFloat) {
        let x = xPosition(for: index)
        let radius = cornerRadius
        drawVertical(in: &path, at: index, from: verticalStart, to: y - radius)
        drawHorizontal(in: &path, from: x + radius, to: x + halfCharacterWidth, y: y)
        drawCurve(in: &path, from: CGPoint(x: x, y: y - radius), to: CGPoint(x: x + radius, y: y), control: CGPoint(x: x, y: y))
    }

    private func drawCornerLeftDown(in path: inout Path, at index: Int, y: CGFloat, verticalEnd: CGFloat) {
        let x = xPosition(for: index)
        let radius = cornerRadius
        drawVertical(in: &path, at: index, from: y + radius, to: verticalEnd)
        drawHorizontal(in: &path, from: x - halfCharacterWidth, to: x - radius, y: y)
        drawCurve(in: &path, from: CGPoint(x: x - radius, y: y), to: CGPoint(x: x, y: y + radius), control: CGPoint(x: x, y: y))
    }

    private func drawCornerLeftUp(in path: inout Path, at index: Int, y: CGFloat, verticalStart: CGFloat) {
        let x = xPosition(for: index)
        let radius = cornerRadius
        drawVertical(in: &path, at: index, from: verticalStart, to: y - radius)
        drawHorizontal(in: &path, from: x - halfCharacterWidth, to: x - radius, y: y)
        drawCurve(in: &path, from: CGPoint(x: x - radius, y: y), to: CGPoint(x: x, y: y - radius), control: CGPoint(x: x, y: y))
    }

    private var cornerRadius: CGFloat {
        min(JjGraphMetrics.cornerRadius, halfCharacterWidth)
    }

    private func drawCurve(in path: inout Path, from start: CGPoint, to end: CGPoint, control: CGPoint) {
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
    }

    private func drawLine(in path: inout Path, from start: CGPoint, to end: CGPoint) {
        path.move(to: start)
        path.addLine(to: end)
    }

    private func rightSideClosesFromAbove(_ characters: [Character], after index: Int) -> Bool {
        for character in characters.dropFirst(index + 1) {
            if character == "╯" { return true }
            if character != "─", !character.isWhitespace { return false }
        }
        return false
    }

    @ViewBuilder
    private func nodeElement(_ character: Character, at index: Int) -> some View {
        if character == "@" {
            Text("@")
                .font(.system(size: 11, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(MuxyTheme.accent)
                .frame(width: JjGraphMetrics.characterWidth)
                .position(x: xPosition(for: index), y: height / 2)
        } else if character == "◆" {
            Rectangle()
                .fill(MuxyTheme.fgDim)
                .frame(width: JjGraphMetrics.nodeSize, height: JjGraphMetrics.nodeSize)
                .rotationEffect(.degrees(45))
                .position(x: xPosition(for: index), y: height / 2)
        } else {
            Circle()
                .stroke(MuxyTheme.fgDim.opacity(0.86), lineWidth: JjGraphMetrics.nodeStroke)
                .frame(width: JjGraphMetrics.nodeSize, height: JjGraphMetrics.nodeSize)
                .position(x: xPosition(for: index), y: height / 2)
        }
    }

    private func graphCharacter(_ line: String?, at index: Int) -> Character? {
        guard let line else { return nil }
        let characters = Array(line)
        guard characters.indices.contains(index) else { return nil }
        return characters[index]
    }

    private func connectsToRowBelow(_ character: Character) -> Bool {
        "│├┤┼┬╮╭".contains(character)
    }

    private func connectsFromRowAbove(_ character: Character) -> Bool {
        "│├┤┼┴╯╰".contains(character)
    }

    private func closesAtTransition(_ character: Character) -> Bool {
        "┴╯╰".contains(character)
    }

    private func xPosition(for index: Int) -> CGFloat {
        CGFloat(index) * JjGraphMetrics.characterWidth + JjGraphMetrics.characterWidth / 2
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
