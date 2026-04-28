import MuxyShared
import SwiftUI

struct JjPanelView: View {
    @Bindable var state: JjPanelState
    @State private var showDescribeSheet = false
    @State private var showCommitSheet = false
    @State private var actionError: String?

    private let mutator = JjMutationService(queue: JjProcessQueue.shared)
    private let bookmarkService = JjBookmarkService(queue: JjProcessQueue.shared)

    @State private var showCreateBookmarkSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            actionBar
            if let actionError {
                Text(actionError)
                    .font(.system(size: 11))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
                    .padding(.horizontal, 4)
            }
            if let snapshot = state.snapshot {
                changeCard(snapshot: snapshot)
                Divider()
                fileList(entries: snapshot.parentDiff)
                if !snapshot.bookmarks.isEmpty {
                    bookmarkList(bookmarks: snapshot.bookmarks)
                }
                if !snapshot.conflicts.isEmpty {
                    conflictList(conflicts: snapshot.conflicts)
                }
            } else if let error = state.errorMessage {
                errorBanner(message: error)
            } else if state.isLoading {
                loadingBanner
            } else {
                emptyState
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await state.refresh() }
        .sheet(isPresented: $showDescribeSheet) {
            JjMessageSheet(
                title: "Describe Change",
                confirmLabel: "Save",
                onConfirm: { message in
                    showDescribeSheet = false
                    runMutation { try await mutator.describe(repoPath: state.repoPath, message: message) }
                },
                onCancel: { showDescribeSheet = false }
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
                    showCreateBookmarkSheet = false
                    runMutation {
                        try await bookmarkService.create(
                            repoPath: state.repoPath,
                            name: name,
                            revset: "@"
                        )
                    }
                },
                onCancel: { showCreateBookmarkSheet = false }
            )
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
    }

    private func fileList(entries: [JjStatusEntry]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Files")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                Text("(\(entries.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
            if entries.isEmpty {
                Text("No changes vs parent")
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

    private func color(for change: JjFileChange) -> Color {
        switch change {
        case .added, .copied: MuxyTheme.diffAddFg
        case .deleted: MuxyTheme.diffRemoveFg
        case .modified, .renamed: MuxyTheme.fgMuted
        }
    }

    private func bookmarkList(bookmarks: [JjBookmark]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Bookmarks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.fg)
                Text("(\(bookmarks.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
                Spacer()
                Button {
                    showCreateBookmarkSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .help("New bookmark")
            }
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

    private func conflictList(conflicts: [JjConflict]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
                Text("Conflicts")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MuxyTheme.diffRemoveFg)
                Text("(\(conflicts.count))")
                    .font(.system(size: 10))
                    .foregroundStyle(MuxyTheme.fgDim)
            }
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
        .padding(8)
        .background(MuxyTheme.surface, in: RoundedRectangle(cornerRadius: 6))
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
            onBackout: { runMutation { try await mutator.backout(repoPath: state.repoPath) } }
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
}
