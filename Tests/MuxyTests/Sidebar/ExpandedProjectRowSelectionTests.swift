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

    @Test("workspace row handles first mouse down as selection")
    func workspaceRowHandlesFirstMouseDownAsSelection() {
        #expect(ExpandedWorktreeRowClickPolicy.action(forClickCount: 1) == .select)
    }

    @Test("workspace row handles repeated mouse down as double click")
    func workspaceRowHandlesRepeatedMouseDownAsDoubleClick() {
        #expect(ExpandedWorktreeRowClickPolicy.action(forClickCount: 2) == .doubleClick)
        #expect(ExpandedWorktreeRowClickPolicy.action(forClickCount: 3) == .doubleClick)
    }

    @Test("workspace row background emphasizes only waiting and completed agents")
    func workspaceRowBackgroundEmphasizesOnlyWaitingAndCompletedAgents() {
        #expect(ExpandedWorktreeRowBackgroundKind.resolve(dominantState: nil, hovered: false) == .neutral)
        #expect(ExpandedWorktreeRowBackgroundKind.resolve(dominantState: .idle, hovered: false) == .neutral)
        #expect(ExpandedWorktreeRowBackgroundKind.resolve(dominantState: .running, hovered: false) == .neutral)
        #expect(ExpandedWorktreeRowBackgroundKind.resolve(dominantState: .exited, hovered: false) == .neutral)
        #expect(ExpandedWorktreeRowBackgroundKind.resolve(dominantState: .needsInput, hovered: false) == .needsInput)
        #expect(ExpandedWorktreeRowBackgroundKind.resolve(dominantState: .completed, hovered: false) == .completed)
        #expect(ExpandedWorktreeRowBackgroundKind.resolve(dominantState: .running, hovered: true) == .hover)
    }

    @Test("project expands for active or agent-bearing vcs projects")
    func projectExpandsForActiveOrAgentBearingVcsProjects() {
        #expect(ExpandedProjectRow.shouldExpandProjectWorktrees(
            isActive: true,
            isVcsRepo: true,
            hasAgentTabs: false
        ))
        #expect(ExpandedProjectRow.shouldExpandProjectWorktrees(
            isActive: false,
            isVcsRepo: true,
            hasAgentTabs: true
        ))
        #expect(!ExpandedProjectRow.shouldExpandProjectWorktrees(
            isActive: false,
            isVcsRepo: true,
            hasAgentTabs: false
        ))
        #expect(!ExpandedProjectRow.shouldExpandProjectWorktrees(
            isActive: true,
            isVcsRepo: false,
            hasAgentTabs: true
        ))
    }
}
