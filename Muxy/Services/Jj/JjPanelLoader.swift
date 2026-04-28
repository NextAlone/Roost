import Foundation
import MuxyShared

struct JjPanelLoader {
    private let showLoader: @Sendable (String) async throws -> JjShowOutput
    private let statusLoader: @Sendable (String) async throws -> JjStatus
    private let summaryLoader: @Sendable (String, String) async throws -> [JjStatusEntry]
    private let bookmarksLoader: @Sendable (String) async throws -> [JjBookmark]
    private let conflictsLoader: @Sendable (String) async throws -> [JjConflict]

    init(
        showLoader: @escaping @Sendable (String) async throws -> JjShowOutput = Self.defaultShow,
        statusLoader: @escaping @Sendable (String) async throws -> JjStatus = Self.defaultStatus,
        summaryLoader: @escaping @Sendable (String, String) async throws -> [JjStatusEntry] = Self.defaultSummary,
        bookmarksLoader: @escaping @Sendable (String) async throws -> [JjBookmark] = Self.defaultBookmarks,
        conflictsLoader: @escaping @Sendable (String) async throws -> [JjConflict] = Self.defaultConflicts
    ) {
        self.showLoader = showLoader
        self.statusLoader = statusLoader
        self.summaryLoader = summaryLoader
        self.bookmarksLoader = bookmarksLoader
        self.conflictsLoader = conflictsLoader
    }

    func load(repoPath: String) async throws -> JjPanelSnapshot {
        let show = try await showLoader(repoPath)
        let status = try await statusLoader(repoPath)
        let parentDiff = await (try? summaryLoader(repoPath, "@-")) ?? []
        let bookmarks = await (try? bookmarksLoader(repoPath)) ?? []
        let conflicts: [JjConflict] = if status.hasConflicts {
            await (try? conflictsLoader(repoPath)) ?? []
        } else {
            []
        }
        return JjPanelSnapshot(
            show: show,
            parentDiff: parentDiff,
            status: status,
            bookmarks: bookmarks,
            conflicts: conflicts
        )
    }

    private static let defaultShow: @Sendable (String) async throws -> JjShowOutput = { repoPath in
        try await JjRepositoryService().show(repoPath: repoPath, revset: "@")
    }

    private static let defaultStatus: @Sendable (String) async throws -> JjStatus = { repoPath in
        let result = try await JjProcessRunner.run(
            repoPath: repoPath,
            command: ["status"],
            snapshot: .ignore,
            atOp: nil
        )
        guard result.status == 0 else {
            throw JjPanelLoaderError.statusFailed(stderr: result.stderr)
        }
        let raw = String(data: result.stdout, encoding: .utf8) ?? ""
        return try JjStatusParser.parse(raw)
    }

    private static let defaultSummary: @Sendable (String, String) async throws -> [JjStatusEntry] = { repoPath, revset in
        try await JjDiffService().summary(repoPath: repoPath, revset: revset)
    }

    private static let defaultBookmarks: @Sendable (String) async throws -> [JjBookmark] = { repoPath in
        try await JjBookmarkService(queue: JjProcessQueue.shared).list(repoPath: repoPath)
    }

    private static let defaultConflicts: @Sendable (String) async throws -> [JjConflict] = { repoPath in
        try await JjConflictsService(queue: JjProcessQueue.shared).list(repoPath: repoPath)
    }
}

enum JjPanelLoaderError: Error {
    case statusFailed(stderr: String)
}
