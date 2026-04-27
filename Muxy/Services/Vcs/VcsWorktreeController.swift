import Foundation
import MuxyShared

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
