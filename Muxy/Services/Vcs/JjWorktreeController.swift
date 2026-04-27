import Foundation
import MuxyShared

struct JjWorktreeController: VcsWorktreeController {
    private let workspaceList: @Sendable (String) async throws -> [JjWorkspaceEntry]
    private let workspaceAdd: @Sendable (String, String, String) async throws -> Void
    private let workspaceForget: @Sendable (String, String) async throws -> Void
    private let bookmarkCreate: @Sendable (String, String) async throws -> Void
    private let bookmarkForget: @Sendable (String, String) async throws -> Void

    init(
        workspaceList: @escaping @Sendable (String) async throws -> [JjWorkspaceEntry] = Self.defaultWorkspaceList,
        workspaceAdd: @escaping @Sendable (String, String, String) async throws -> Void = Self.defaultWorkspaceAdd,
        workspaceForget: @escaping @Sendable (String, String) async throws -> Void = Self.defaultWorkspaceForget,
        bookmarkCreate: @escaping @Sendable (String, String) async throws -> Void = Self.defaultBookmarkCreate,
        bookmarkForget: @escaping @Sendable (String, String) async throws -> Void = Self.defaultBookmarkForget
    ) {
        self.workspaceList = workspaceList
        self.workspaceAdd = workspaceAdd
        self.workspaceForget = workspaceForget
        self.bookmarkCreate = bookmarkCreate
        self.bookmarkForget = bookmarkForget
    }

    func addWorktree(
        repoPath: String,
        name: String,
        path: String,
        ref: String?,
        createRef: Bool
    ) async throws {
        try await workspaceAdd(repoPath, name, path)
        if createRef {
            let refName = ref ?? name
            try await bookmarkCreate(repoPath, refName)
        }
    }

    func removeWorktree(
        repoPath: String,
        path: String,
        force: Bool
    ) async throws {
        let entries = try await workspaceList(repoPath)
        let leaf = (path as NSString).lastPathComponent
        if let match = entries.first(where: { $0.name == leaf }) {
            try await workspaceForget(repoPath, match.name)
        } else if entries.count == 1, let only = entries.first {
            try await workspaceForget(repoPath, only.name)
        }
        try? FileManager.default.removeItem(atPath: path)
    }

    func deleteRef(repoPath: String, name: String) async throws {
        try await bookmarkForget(repoPath, name)
    }

    private static let defaultWorkspaceList: @Sendable (String) async throws -> [JjWorkspaceEntry] = { repoPath in
        let service = JjWorkspaceService(queue: JjProcessQueue.shared)
        return try await service.list(repoPath: repoPath)
    }

    private static let defaultWorkspaceAdd: @Sendable (String, String, String) async throws -> Void = { repoPath, name, path in
        let service = JjWorkspaceService(queue: JjProcessQueue.shared)
        try await service.add(repoPath: repoPath, name: name, path: path)
    }

    private static let defaultWorkspaceForget: @Sendable (String, String) async throws -> Void = { repoPath, name in
        let service = JjWorkspaceService(queue: JjProcessQueue.shared)
        try await service.forget(repoPath: repoPath, name: name)
    }

    private static let defaultBookmarkCreate: @Sendable (String, String) async throws -> Void = { repoPath, name in
        let service = JjBookmarkService(queue: JjProcessQueue.shared)
        try await service.create(repoPath: repoPath, name: name, revset: nil)
    }

    private static let defaultBookmarkForget: @Sendable (String, String) async throws -> Void = { repoPath, name in
        let service = JjBookmarkService(queue: JjProcessQueue.shared)
        try await service.forget(repoPath: repoPath, name: name)
    }
}
