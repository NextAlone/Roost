import Foundation

struct GitWorktreeController: VcsWorktreeController {
    func addWorktree(
        repoPath: String,
        name: String,
        path: String,
        ref: String?,
        createRef: Bool
    ) async throws {
        let branch = ref ?? name
        try await GitWorktreeService.shared.addWorktree(
            repoPath: repoPath,
            path: path,
            branch: branch,
            createBranch: createRef
        )
    }

    func removeWorktree(
        repoPath: String,
        path: String,
        target _: VcsWorktreeRemovalTarget,
        force: Bool
    ) async throws {
        try await GitWorktreeService.shared.removeWorktree(
            repoPath: repoPath,
            path: path,
            force: force
        )
    }

    func deleteRef(repoPath: String, name: String) async throws {
        try await GitWorktreeService.shared.deleteBranch(repoPath: repoPath, branch: name)
    }
}
