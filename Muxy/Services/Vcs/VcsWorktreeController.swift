import Foundation
import MuxyShared

/// Worktree CRUD over the active VCS.
///
/// `force` semantics on `removeWorktree`:
/// - git: `git worktree remove --force` — required to remove worktrees with uncommitted changes
/// - jj: ignored — `jj workspace forget` always cleans state regardless; no force concept
///
/// `identifier` semantics on `removeWorktree`:
/// - git: ignored (path is the identity)
/// - jj: workspace name; nil falls back to leaf-name match (orphan-sweep path)
protocol VcsWorktreeController: Sendable {
    func addWorktree(
        repoPath: String,
        name: String,
        path: String,
        ref: String?,
        createRef: Bool
    ) async throws

    func removeWorktree(
        repoPath: String,
        path: String,
        identifier: String?,
        force: Bool
    ) async throws

    func deleteRef(repoPath: String, name: String) async throws
}

enum VcsWorktreeControllerFactory {
    static func controller(for kind: VcsKind) -> any VcsWorktreeController {
        switch kind {
        case .git:
            return GitWorktreeController()
        case .jj:
            return JjWorktreeController()
        }
    }
}
