import Foundation

struct GitStatusProbe: VcsStatusProbe {
    func hasUncommittedChanges(at worktreePath: String) async -> Bool {
        await GitWorktreeService.shared.hasUncommittedChanges(worktreePath: worktreePath)
    }
}
