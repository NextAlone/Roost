import AppKit
import Foundation
import MuxyShared
import SwiftUI

struct JjPanelView: View {
    @Bindable var state: JjPanelState
    let onOpenFile: (String) -> Void
    @State private var showDescribeSheet = false
    @State private var showCommitSheet = false
    @State private var actionError: String?
    @State private var pendingDescribeChange: JjLogEntry?
    @State private var changesRevsetDraft = ""
    @State private var filesCollapsed = false
    @State private var changesCollapsed = false
    @State private var bookmarksCollapsed = true
    @State private var operationsCollapsed = true
    @State private var conflictsCollapsed = false
    @State private var contextTargetChangeID: String?
    @State private var contextTargetOperationID: String?
    @State private var contextTargetConflictPath: String?
    @State private var hoveredChangeID: String?
    @State private var hoveredOperationID: String?
    @State private var hoveredConflictPath: String?
    @State private var showRestoreOperationAlert = false
    @State private var pendingRestoreOperation: JjOperation?
    @State private var conflictContent: JjConflictContent?

    private let mutator = JjMutationService(queue: JjProcessQueue.shared)
    private let bookmarkService = JjBookmarkService(queue: JjProcessQueue.shared)
    private let conflictContentLoader = JjConflictContentLoader()

    @State private var showCreateBookmarkSheet = false
    @State private var pendingCreateBookmarkRevset: String?
    @State private var showRenameBookmarkSheet = false
    @State private var pendingRenameBookmark: JjBookmark?
    private static let sectionHeaderHeight: CGFloat = 30

    init(state: JjPanelState, onOpenFile: @escaping (String) -> Void = { _ in }) {
        self.state = state
        self.onOpenFile = onOpenFile
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            actionBar
            if let inlineError {
                Text(inlineError)
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
        .task {
            changesRevsetDraft = state.activeChangesRevset
            await state.refresh()
        }
        .sheet(isPresented: $showDescribeSheet) {
            JjMessageSheet(
                title: "Describe Change",
                confirmLabel: "Save",
                onConfirm: { message in
                    showDescribeSheet = false
                    if let pendingDescribeChange {
                        let revset = pendingDescribeChange.actionRevset
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
        .sheet(isPresented: $showRenameBookmarkSheet) {
            if let bookmark = pendingRenameBookmark {
                JjBookmarkCreateSheet(
                    title: "Rename Bookmark",
                    confirmLabel: "Rename",
                    initialName: bookmark.name,
                    targetLabel: nil,
                    onConfirm: { name in
                        let oldName = bookmark.name
                        pendingRenameBookmark = nil
                        showRenameBookmarkSheet = false
                        guard name != oldName else { return }
                        runMutation {
                            try await bookmarkService.rename(
                                repoPath: state.repoPath,
                                oldName: oldName,
                                newName: name
                            )
                        }
                    },
                    onCancel: {
                        pendingRenameBookmark = nil
                        showRenameBookmarkSheet = false
                    }
                )
            }
        }
        .sheet(item: $conflictContent) { content in
            JjConflictContentSheet(
                content: content,
                onOpenInEditor: {
                    onOpenFile(content.path)
                    conflictContent = nil
                },
                onClose: {
                    conflictContent = nil
                }
            )
        }
        .alert("Restore Repository State?", isPresented: $showRestoreOperationAlert, presenting: pendingRestoreOperation) { operation in
            Button("Cancel", role: .cancel) {
                pendingRestoreOperation = nil
            }
            Button("Restore", role: .destructive) {
                pendingRestoreOperation = nil
                runMutation {
                    try await mutator.restoreOperation(repoPath: state.repoPath, id: operation.id)
                }
            }
        } message: { operation in
            Text("Restore repository state to operation \(operation.id). Remote-tracking bookmarks will not be restored.")
        }
        .onChange(of: showRestoreOperationAlert) { _, isPresented in
            if !isPresented {
                pendingRestoreOperation = nil
            }
        }
    }

    private var inlineError: String? {
        actionError ?? (state.snapshot == nil ? nil : state.errorMessage)
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
        if !snapshot.operations.isEmpty {
            sections.append(.operations)
        }
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
        case .operations:
            operationLogContent(operations: snapshot.operations)
        case .conflicts:
            conflictListContent(conflicts: snapshot.conflicts)
        }
    }

    private func sectionCount(_ section: JjPanelSection, snapshot: JjPanelSnapshot) -> Int {
        switch section {
        case .files: snapshot.status.entries.count
        case .changes: snapshot.changes.count
        case .bookmarks: snapshot.bookmarks.count
        case .operations: snapshot.operations.count
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

            if section == .changes {
                changesRevsetControls
            } else if section == .bookmarks {
                Button {
                    runMutation {
                        try await bookmarkService.fetchTracked(repoPath: state.repoPath)
                    }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("Fetch tracked bookmarks")

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

    private var changesRevsetControls: some View {
        HStack(spacing: 5) {
            TextField("Revset", text: $changesRevsetDraft)
                .font(.system(size: 10, design: .monospaced))
                .textFieldStyle(.plain)
                .padding(.horizontal, 6)
                .frame(width: 150, height: 20)
                .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(MuxyTheme.border, lineWidth: 1)
                )
                .disabled(state.isLoading)
                .onSubmit(applyChangesRevset)

            Button(action: applyChangesRevset) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .disabled(state.isLoading || changesRevsetDraftTrimmed == state.activeChangesRevset)
            .help("Apply revset")
            .accessibilityLabel("Apply revset")

            Button(action: resetChangesRevset) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .disabled(state.isLoading || (state.activeChangesRevset.isEmpty && changesRevsetDraft.isEmpty))
            .help("Reset revset")
            .accessibilityLabel("Reset revset")
        }
    }

    private var changesRevsetDraftTrimmed: String {
        changesRevsetDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isCollapsed(_ section: JjPanelSection) -> Bool {
        switch section {
        case .files: filesCollapsed
        case .changes: changesCollapsed
        case .bookmarks: bookmarksCollapsed
        case .operations: operationsCollapsed
        case .conflicts: conflictsCollapsed
        }
    }

    private func toggleSection(_ section: JjPanelSection) {
        switch section {
        case .files: filesCollapsed.toggle()
        case .changes: changesCollapsed.toggle()
        case .bookmarks: bookmarksCollapsed.toggle()
        case .operations: operationsCollapsed.toggle()
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
                    ForEach(Array(entries.enumerated()), id: \.element.rowIdentity) { index, entry in
                        let rowID = entry.rowIdentity
                        let actionRevset = entry.actionRevset
                        VStack(alignment: .leading, spacing: 0) {
                            JjChangeRow(
                                entry: entry,
                                bookmarks: bookmarks,
                                graphColumnWidth: graphColumnWidth,
                                isHovered: hoveredChangeID == rowID,
                                isContextTarget: contextTargetChangeID == rowID,
                                previousGraphLine: index > 0 ? entries[index - 1].graphLinesAfter.last : nil,
                                nextGraphLine: entry.graphLinesAfter.first,
                                onHoverChange: { isHovered in
                                    if isHovered {
                                        hoveredChangeID = rowID
                                    } else if hoveredChangeID == rowID {
                                        hoveredChangeID = nil
                                    }
                                },
                                onRightMouseDown: {
                                    hoveredChangeID = nil
                                    hoveredOperationID = nil
                                    hoveredConflictPath = nil
                                    contextTargetChangeID = rowID
                                    contextTargetOperationID = nil
                                    contextTargetConflictPath = nil
                                },
                                onContextMenuAppear: {
                                    contextTargetChangeID = rowID
                                    contextTargetOperationID = nil
                                    contextTargetConflictPath = nil
                                },
                                onContextMenuDisappear: {
                                    if contextTargetChangeID == rowID {
                                        contextTargetChangeID = nil
                                    }
                                },
                                onCopyChangeID: { copyToPasteboard(entry.change.prefix) },
                                onCopyCommitID: { copyToPasteboard(entry.commitId) },
                                onCopyDescription: { copyToPasteboard(entry.description) },
                                onEdit: {
                                    runMutation {
                                        try await mutator.edit(
                                            repoPath: state.repoPath,
                                            revset: actionRevset
                                        )
                                    }
                                },
                                onDescribe: {
                                    pendingDescribeChange = entry
                                    showDescribeSheet = true
                                },
                                onNewAt: {
                                    runMutation { try await mutator.newAt(repoPath: state.repoPath, revset: actionRevset) }
                                },
                                onNewAfter: {
                                    runMutation { try await mutator.newAfter(repoPath: state.repoPath, revset: actionRevset) }
                                },
                                onNewBefore: {
                                    runMutation { try await mutator.newBefore(repoPath: state.repoPath, revset: actionRevset) }
                                },
                                onDuplicate: {
                                    runMutation { try await mutator.duplicate(repoPath: state.repoPath, revset: actionRevset) }
                                },
                                onSquashInto: {
                                    runMutation { try await mutator.squashInto(repoPath: state.repoPath, revset: actionRevset) }
                                },
                                onRebaseOnto: {
                                    runMutation {
                                        try await mutator.rebaseWorkingCopyOnto(repoPath: state.repoPath, revset: actionRevset)
                                    }
                                },
                                onCreateBookmark: {
                                    pendingCreateBookmarkRevset = actionRevset
                                    showCreateBookmarkSheet = true
                                },
                                onMoveBookmark: { bookmarkName in
                                    runMutation {
                                        try await bookmarkService.setTarget(
                                            repoPath: state.repoPath,
                                            name: bookmarkName,
                                            revset: actionRevset
                                        )
                                    }
                                },
                                onAbandon: {
                                    runMutation { try await mutator.abandon(repoPath: state.repoPath, revset: actionRevset) }
                                },
                                onRevert: {
                                    runMutation { try await mutator.revert(repoPath: state.repoPath, revset: actionRevset) }
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
                            Button("Push") {
                                runMutation {
                                    try await bookmarkService.push(
                                        repoPath: state.repoPath,
                                        name: bookmark.name
                                    )
                                }
                            }
                            .disabled(!bookmark.isLocal)

                            Button("Rename...") {
                                pendingRenameBookmark = bookmark
                                showRenameBookmarkSheet = true
                            }
                            .disabled(!bookmark.isLocal)

                            Divider()

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
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 9))
                                .foregroundStyle(MuxyTheme.diffRemoveFg)
                                .frame(width: 12)
                            Text(conflict.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MuxyTheme.fg)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .background(
                            JjRowHighlight.resolve(
                                isHovered: hoveredConflictPath == conflict.path,
                                isContextTarget: contextTargetConflictPath == conflict.path
                            ).background
                        )
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            if isHovered {
                                hoveredConflictPath = conflict.path
                            } else if hoveredConflictPath == conflict.path {
                                hoveredConflictPath = nil
                            }
                        }
                        .background(
                            JjRightClickObserver {
                                hoveredChangeID = nil
                                hoveredOperationID = nil
                                hoveredConflictPath = nil
                                contextTargetChangeID = nil
                                contextTargetOperationID = nil
                                contextTargetConflictPath = conflict.path
                            }
                        )
                        .contextMenu {
                            JjContextMenuLifecycle(
                                onAppear: {
                                    contextTargetChangeID = nil
                                    contextTargetOperationID = nil
                                    contextTargetConflictPath = conflict.path
                                },
                                onDisappear: {
                                    if contextTargetConflictPath == conflict.path {
                                        contextTargetConflictPath = nil
                                    }
                                }
                            )
                            Button("View Content…") {
                                loadConflictContent(conflict)
                            }
                            Button("Open in Editor") {
                                onOpenFile(conflict.path)
                            }

                            Divider()

                            Button("Use Ours", role: .destructive) {
                                runMutation {
                                    try await mutator.resolveConflict(
                                        repoPath: state.repoPath,
                                        path: conflict.path,
                                        tool: .ours
                                    )
                                }
                            }
                            Button("Use Theirs", role: .destructive) {
                                runMutation {
                                    try await mutator.resolveConflict(
                                        repoPath: state.repoPath,
                                        path: conflict.path,
                                        tool: .theirs
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func operationLogContent(operations: [JjOperation]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if operations.isEmpty {
                Text("No operations")
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.fgDim)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(operations, id: \.id) { operation in
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 9))
                                .foregroundStyle(MuxyTheme.accent)
                                .frame(width: 12)
                            Text(operation.id)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MuxyTheme.accent)
                            Text(operation.description.isEmpty ? "(no description)" : operation.description)
                                .font(.system(size: 11))
                                .foregroundStyle(MuxyTheme.fg)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                            Text(relativeDate(operation.timestamp))
                                .font(.system(size: 10))
                                .foregroundStyle(MuxyTheme.fgDim)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .background(
                            JjRowHighlight.resolve(
                                isHovered: hoveredOperationID == operation.id,
                                isContextTarget: contextTargetOperationID == operation.id
                            ).background
                        )
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            if isHovered {
                                hoveredOperationID = operation.id
                            } else if hoveredOperationID == operation.id {
                                hoveredOperationID = nil
                            }
                        }
                        .background(
                            JjRightClickObserver {
                                hoveredChangeID = nil
                                hoveredOperationID = nil
                                hoveredConflictPath = nil
                                contextTargetChangeID = nil
                                contextTargetOperationID = operation.id
                                contextTargetConflictPath = nil
                            }
                        )
                        .contextMenu {
                            JjContextMenuLifecycle(
                                onAppear: {
                                    contextTargetOperationID = operation.id
                                    contextTargetChangeID = nil
                                    contextTargetConflictPath = nil
                                },
                                onDisappear: {
                                    if contextTargetOperationID == operation.id {
                                        contextTargetOperationID = nil
                                    }
                                }
                            )
                            Button("Restore Repository to This Operation", role: .destructive) {
                                pendingRestoreOperation = operation
                                showRestoreOperationAlert = true
                            }
                        }
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

    private func applyChangesRevset() {
        Task {
            await state.applyChangesRevset(changesRevsetDraft)
            changesRevsetDraft = state.activeChangesRevset
        }
    }

    private func resetChangesRevset() {
        Task {
            await state.resetChangesRevset()
            changesRevsetDraft = state.activeChangesRevset
        }
    }

    private func loadConflictContent(_ conflict: JjConflict) {
        Task {
            do {
                conflictContent = try await conflictContentLoader.load(repoPath: state.repoPath, path: conflict.path)
                actionError = nil
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
    case operations
    case conflicts

    var title: String {
        switch self {
        case .files: "Files"
        case .changes: "Changes"
        case .bookmarks: "Bookmarks"
        case .operations: "Operation Log"
        case .conflicts: "Conflicts"
        }
    }
}

enum JjRowHighlight: Equatable {
    case none
    case hover
    case contextTarget

    static func resolve(isHovered: Bool, isContextTarget: Bool) -> JjRowHighlight {
        if isContextTarget { return .contextTarget }
        if isHovered { return .hover }
        return .none
    }

    @MainActor var background: Color {
        switch self {
        case .none: .clear
        case .hover: MuxyTheme.hover
        case .contextTarget: MuxyTheme.surface
        }
    }
}

private struct JjContextMenuLifecycle: View {
    let onAppear: () -> Void
    let onDisappear: () -> Void

    var body: some View {
        EmptyView()
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
    }
}

private struct JjRightClickObserver: NSViewRepresentable {
    let onRightMouseDown: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onRightMouseDown: onRightMouseDown)
    }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.coordinator = context.coordinator
        context.coordinator.view = view
        context.coordinator.installIfNeeded()
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        context.coordinator.onRightMouseDown = onRightMouseDown
        context.coordinator.view = nsView
        context.coordinator.installIfNeeded()
    }

    static func dismantleNSView(_: ObserverView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class ObserverView: NSView {
        weak var coordinator: Coordinator?

        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.installIfNeeded()
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var onRightMouseDown: () -> Void
        weak var view: ObserverView?
        private var monitor: Any?
        private weak var monitoredWindow: NSWindow?

        init(onRightMouseDown: @escaping () -> Void) {
            self.onRightMouseDown = onRightMouseDown
        }

        func installIfNeeded() {
            guard let window = view?.window else {
                remove()
                return
            }
            guard monitor == nil || monitoredWindow !== window else { return }
            remove()
            monitoredWindow = window
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.handle(event)
                }
                return event
            }
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            monitoredWindow = nil
        }

        private func handle(_ event: NSEvent) {
            guard let view, event.window === view.window else { return }
            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else { return }
            onRightMouseDown()
        }
    }
}

private struct JjChangeRow: View {
    let entry: JjLogEntry
    let bookmarks: [JjBookmark]
    let graphColumnWidth: CGFloat
    let isHovered: Bool
    let isContextTarget: Bool
    let previousGraphLine: String?
    let nextGraphLine: String?
    let onHoverChange: (Bool) -> Void
    let onRightMouseDown: () -> Void
    let onContextMenuAppear: () -> Void
    let onContextMenuDisappear: () -> Void
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
                    ForEach(entry.bookmarkLabels, id: \.self) { label in
                        JjChangeBookmarkBadge(label: label)
                    }
                }
            }

            Spacer(minLength: 0)

            if isHovered {
                Text(entry.commitId)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(MuxyTheme.fgDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .background(JjRowHighlight.resolve(isHovered: isHovered, isContextTarget: isContextTarget).background)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChange)
        .background(JjRightClickObserver(onRightMouseDown: onRightMouseDown))
        .contextMenu {
            JjContextMenuLifecycle(onAppear: onContextMenuAppear, onDisappear: onContextMenuDisappear)
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

private struct JjChangeBookmarkBadge: View {
    let label: String

    private var isRemote: Bool {
        label.contains("@")
    }

    private var isConflicted: Bool {
        label.contains("??")
    }

    private var foreground: Color {
        if isConflicted { return MuxyTheme.diffRemoveFg }
        return isRemote ? MuxyTheme.fgMuted : MuxyTheme.accent
    }

    private var background: Color {
        if isConflicted { return MuxyTheme.diffRemoveFg.opacity(0.12) }
        return isRemote ? MuxyTheme.surface : MuxyTheme.accent.opacity(0.12)
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
    return relativeDate(date)
}

private func relativeDate(_ date: Date) -> String {
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
