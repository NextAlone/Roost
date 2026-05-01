import Testing

@testable import Roost

struct WorktreeDisplayNameTests {
    @Test("primary workspace displays as default")
    func primaryWorkspaceDisplaysDefault() {
        let worktree = Worktree(name: "Repo", path: "/tmp/repo", isPrimary: true)

        #expect(worktree.displayWorkspaceName == "default")
    }

    @Test("non-primary workspace displays stored workspace name")
    func nonPrimaryWorkspaceDisplaysStoredName() {
        let worktree = Worktree(name: "feature-a", path: "/tmp/repo-feature-a", isPrimary: false)

        #expect(worktree.displayWorkspaceName == "feature-a")
    }

    @Test("jj workspace name overrides stored label")
    func jjWorkspaceNameOverridesStoredLabel() {
        let worktree = Worktree(
            name: "local-label",
            path: "/tmp/repo-feature-a",
            isPrimary: false,
            jjWorkspaceName: "feature-a"
        )

        #expect(worktree.displayWorkspaceName == "feature-a")
    }
}
