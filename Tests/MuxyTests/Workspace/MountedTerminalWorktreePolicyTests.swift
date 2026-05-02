import Foundation
import Testing

@testable import Roost

@Suite("MountedTerminalWorktreePolicy")
struct MountedTerminalWorktreePolicyTests {
    @Test("includes active key without mounting every available workspace")
    func includesActiveKeyOnly() {
        let active = key(project: 1, worktree: 1)
        let other = key(project: 2, worktree: 1)

        let keys = MountedTerminalWorktreePolicy.displayKeys(
            remembered: [],
            active: active,
            available: [active, other]
        )

        #expect(keys == [active])
    }

    @Test("keeps remembered keys and prunes removed workspaces")
    func keepsRememberedAndPrunesRemoved() {
        let active = key(project: 1, worktree: 1)
        let remembered = key(project: 2, worktree: 1)
        let removed = key(project: 3, worktree: 1)

        let keys = MountedTerminalWorktreePolicy.displayKeys(
            remembered: [remembered, removed],
            active: active,
            available: [active, remembered]
        )

        #expect(Set(keys) == [active, remembered])
    }

    private func key(project: UInt8, worktree: UInt8) -> WorktreeKey {
        WorktreeKey(
            projectID: UUID(uuid: (project, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
            worktreeID: UUID(uuid: (worktree, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        )
    }
}
