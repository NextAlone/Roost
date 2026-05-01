import Foundation
import MuxyShared

struct JjPanelLoader {
    private let showLoader: @Sendable (String) async throws -> JjShowOutput
    private let statusLoader: @Sendable (String) async throws -> JjStatus
    private let changesLoader: @Sendable (String) async throws -> [JjLogEntry]
    private let bookmarksLoader: @Sendable (String) async throws -> [JjBookmark]
    private let conflictsLoader: @Sendable (String) async throws -> [JjConflict]
    private let operationsLoader: @Sendable (String) async throws -> [JjOperation]

    init(
        showLoader: @escaping @Sendable (String) async throws -> JjShowOutput = Self.defaultShow,
        statusLoader: @escaping @Sendable (String) async throws -> JjStatus = Self.defaultStatus,
        changesLoader: @escaping @Sendable (String) async throws -> [JjLogEntry] = Self.defaultChanges,
        bookmarksLoader: @escaping @Sendable (String) async throws -> [JjBookmark] = Self.defaultBookmarks,
        conflictsLoader: @escaping @Sendable (String) async throws -> [JjConflict] = Self.defaultConflicts,
        operationsLoader: @escaping @Sendable (String) async throws -> [JjOperation] = Self.defaultOperations
    ) {
        self.showLoader = showLoader
        self.statusLoader = statusLoader
        self.changesLoader = changesLoader
        self.bookmarksLoader = bookmarksLoader
        self.conflictsLoader = conflictsLoader
        self.operationsLoader = operationsLoader
    }

    func load(repoPath: String) async throws -> JjPanelSnapshot {
        let show = try await showLoader(repoPath)
        let status = try await statusLoader(repoPath)
        let changes = await (try? changesLoader(repoPath)) ?? []
        let bookmarks = await (try? bookmarksLoader(repoPath)) ?? []
        let conflicts: [JjConflict] = if status.hasConflicts {
            await (try? conflictsLoader(repoPath)) ?? []
        } else {
            []
        }
        let operations = await (try? operationsLoader(repoPath)) ?? []
        return JjPanelSnapshot(
            show: show,
            status: status,
            changes: changes,
            bookmarks: bookmarks,
            conflicts: conflicts,
            operations: operations
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

    private static let defaultChanges: @Sendable (String) async throws -> [JjLogEntry] = { repoPath in
        try await JjRepositoryService().log(repoPath: repoPath)
    }

    private static let defaultBookmarks: @Sendable (String) async throws -> [JjBookmark] = { repoPath in
        try await JjBookmarkService(queue: JjProcessQueue.shared).list(repoPath: repoPath)
    }

    private static let defaultConflicts: @Sendable (String) async throws -> [JjConflict] = { repoPath in
        try await JjConflictsService(queue: JjProcessQueue.shared).list(repoPath: repoPath)
    }

    private static let defaultOperations: @Sendable (String) async throws -> [JjOperation] = { repoPath in
        try await JjRepositoryService().operationLog(repoPath: repoPath)
    }
}

enum JjPanelLoaderError: Error {
    case statusFailed(stderr: String)
}
