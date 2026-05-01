import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("ExpandedProjectRow selection")
struct ExpandedProjectRowSelectionTests {
    @Test("workspace row selected only for active project")
    func workspaceRowSelectedOnlyForActiveProject() {
        let activeProjectID = UUID()
        let inactiveProjectID = UUID()
        let worktreeID = UUID()

        #expect(ExpandedProjectRow.isWorktreeSelected(
            projectID: inactiveProjectID,
            worktreeID: worktreeID,
            activeProjectID: activeProjectID,
            activeWorktreeID: worktreeID
        ) == false)

        #expect(ExpandedProjectRow.isWorktreeSelected(
            projectID: activeProjectID,
            worktreeID: worktreeID,
            activeProjectID: activeProjectID,
            activeWorktreeID: worktreeID
        ))
    }

    @Test("workspace row not selected without active workspace")
    func workspaceRowNotSelectedWithoutActiveWorkspace() {
        let projectID = UUID()

        #expect(ExpandedProjectRow.isWorktreeSelected(
            projectID: projectID,
            worktreeID: UUID(),
            activeProjectID: projectID,
            activeWorktreeID: nil
        ) == false)
    }

    @Test("jj workspace has no warning badge")
    func jjWorkspaceHasNoWarningBadge() {
        #expect(VcsKind.jj.sidebarWarningBadgeLabel == nil)
    }

    @Test("git workspace shows warning badge")
    func gitWorkspaceShowsWarningBadge() {
        #expect(VcsKind.git.sidebarWarningBadgeLabel == "GIT")
    }
}
