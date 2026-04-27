import Foundation
import MuxyShared

/// Removal target — encodes whether the caller knows the workspace identity
/// or is sweeping an orphaned directory.
enum VcsWorktreeRemovalTarget: Sendable {
    /// Caller has the workspace identifier (e.g. jj workspace name).
    case identified(String)
    /// Orphan sweep — caller does not know the identifier; controller may
    /// fall back to a leaf-name heuristic. For git this case is identical
    /// to `.identified` (path is the identity).
    case orphan
}

/// Worktree CRUD over the active VCS.
///
/// `force` semantics on `removeWorktree`:
/// - git: `git worktree remove --force` — required to remove worktrees with uncommitted changes
/// - jj: ignored — `jj workspace forget` always cleans state regardless; no force concept
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
        target: VcsWorktreeRemovalTarget,
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
