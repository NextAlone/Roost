import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("AppState agent activity")
struct AppStateAgentActivityTests {
    @Test("updates matching pane activity state")
    func updatesMatchingPane() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let paneID = area.activeTab!.content.pane!.id
        appState.workspaceRoots[key] = .tabArea(area)

        let updated = appState.updateAgentActivity(paneID: paneID, state: .needsInput)

        #expect(updated == true)
        #expect(area.activeTab?.content.pane?.activityState == .needsInput)
    }

    @Test("agent activity updates advance an app-level revision for inactive workspaces")
    func agentActivityUpdatesAdvanceRevisionForInactiveWorkspaces() {
        let appState = makeAppState()
        let projectID = UUID()
        let activeKey = WorktreeKey(projectID: projectID, worktreeID: UUID())
        let inactiveKey = WorktreeKey(projectID: projectID, worktreeID: UUID())
        let activeArea = TabArea(projectPath: "/tmp/active")
        let inactiveArea = TabArea(projectPath: "/tmp/inactive")
        inactiveArea.createAgentTab(kind: .codex)
        let paneID = inactiveArea.activeTab!.content.pane!.id
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = activeKey.worktreeID
        appState.workspaceRoots[activeKey] = .tabArea(activeArea)
        appState.workspaceRoots[inactiveKey] = .tabArea(inactiveArea)

        let revisionBefore = appState.agentActivityRevision
        let updated = appState.updateAgentActivity(paneID: paneID, state: .needsInput)

        #expect(updated == true)
        #expect(inactiveArea.activeTab?.content.pane?.activityState == .needsInput)
        #expect(appState.agentActivityRevision == revisionBefore + 1)
    }

    @Test("done transitions idle to completed")
    func doneTransitionsIdleToCompleted() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let pane = area.activeTab!.content.pane!
        pane.activityState = .idle
        appState.workspaceRoots[key] = .tabArea(area)

        let revisionBefore = appState.agentActivityRevision
        let updated = appState.updateAgentActivity(paneID: pane.id, state: .completed)

        #expect(updated == true)
        #expect(pane.activityState == .completed)
        #expect(appState.agentActivityRevision == revisionBefore + 1)
    }

    @Test("done transitions running to completed")
    func doneTransitionsRunningToCompleted() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let pane = area.activeTab!.content.pane!
        pane.activityState = .running
        appState.workspaceRoots[key] = .tabArea(area)

        let revisionBefore = appState.agentActivityRevision
        let updated = appState.updateAgentActivity(paneID: pane.id, state: .completed)

        #expect(updated == true)
        #expect(pane.activityState == .completed)
        #expect(appState.agentActivityRevision == revisionBefore + 1)
    }

    @Test("done preserves needsInput")
    func donePreservesNeedsInput() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let pane = area.activeTab!.content.pane!
        pane.activityState = .needsInput
        pane.previousActivityState = .running
        appState.workspaceRoots[key] = .tabArea(area)

        let revisionBefore = appState.agentActivityRevision
        let updated = appState.updateAgentActivity(paneID: pane.id, state: .completed)

        #expect(updated == true)
        #expect(pane.activityState == .needsInput)
        #expect(pane.previousActivityState == .running)
        #expect(appState.agentActivityRevision == revisionBefore)
    }

    @Test("done preserves exited")
    func donePreservesExited() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let pane = area.activeTab!.content.pane!
        pane.activityState = .exited
        appState.workspaceRoots[key] = .tabArea(area)

        let revisionBefore = appState.agentActivityRevision
        let updated = appState.updateAgentActivity(paneID: pane.id, state: .completed)

        #expect(updated == true)
        #expect(pane.activityState == .exited)
        #expect(appState.agentActivityRevision == revisionBefore)
    }

    @Test("returns false for missing pane")
    func missingPane() {
        let appState = makeAppState()
        let revisionBefore = appState.agentActivityRevision
        let updated = appState.updateAgentActivity(paneID: UUID(), state: .completed)
        #expect(updated == false)
        #expect(appState.agentActivityRevision == revisionBefore)
    }

    @Test("clears completed agent activity in workspace")
    func clearsCompletedAgentActivityInWorkspace() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        area.activeTab?.content.pane?.activityState = .completed
        appState.workspaceRoots[key] = .tabArea(area)

        let revisionBefore = appState.agentActivityRevision
        let cleared = appState.clearCompletedAgentActivity(for: key)

        #expect(cleared == true)
        #expect(area.activeTab?.content.pane?.activityState == .idle)
        #expect(appState.agentActivityRevision == revisionBefore + 1)
    }

    @Test("does not clear running agent activity in workspace")
    func doesNotClearRunningAgentActivityInWorkspace() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        area.activeTab?.content.pane?.activityState = .running
        appState.workspaceRoots[key] = .tabArea(area)

        let revisionBefore = appState.agentActivityRevision
        let cleared = appState.clearCompletedAgentActivity(for: key)

        #expect(cleared == false)
        #expect(area.activeTab?.content.pane?.activityState == .running)
        #expect(appState.agentActivityRevision == revisionBefore)
    }

    @Test("selecting already active completed agent tab acknowledges it")
    func selectingAlreadyActiveCompletedAgentTabAcknowledgesIt() {
        let appState = makeAppState()
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let tabID = area.activeTabID!
        area.activeTab?.content.pane?.activityState = .completed
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id

        let revisionBefore = appState.agentActivityRevision
        appState.dispatch(.selectTab(projectID: projectID, areaID: area.id, tabID: tabID))

        #expect(area.activeTab?.content.pane?.activityState == .idle)
        #expect(appState.agentActivityRevision == revisionBefore + 1)
    }

    @Test("focusing already focused completed agent area acknowledges it")
    func focusingAlreadyFocusedCompletedAgentAreaAcknowledgesIt() {
        let appState = makeAppState()
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        area.activeTab?.content.pane?.activityState = .completed
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id

        let revisionBefore = appState.agentActivityRevision
        appState.dispatch(.focusArea(projectID: projectID, areaID: area.id))

        #expect(area.activeTab?.content.pane?.activityState == .idle)
        #expect(appState.agentActivityRevision == revisionBefore + 1)
    }

    @Test("marking an agent pane exited advances activity revision")
    func markingAgentPaneExitedAdvancesRevision() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let paneID = area.activeTab!.content.pane!.id
        appState.workspaceRoots[key] = .tabArea(area)

        let revisionBefore = appState.agentActivityRevision
        let marked = appState.markPaneSessionExited(paneID: paneID)

        #expect(marked == true)
        #expect(area.activeTab?.content.pane?.activityState == .exited)
        #expect(area.activeTab?.content.pane?.lastState == .exited)
        #expect(appState.agentActivityRevision == revisionBefore + 1)
    }

    private func makeAppState() -> AppState {
        AppState(
            selectionStore: AgentActivitySelectionStoreStub(),
            terminalViews: AgentActivityTerminalViewRemovingStub(),
            workspacePersistence: AgentActivityWorkspacePersistenceStub()
        )
    }
}

@MainActor
private final class AgentActivitySelectionStoreStub: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

@MainActor
private final class AgentActivityTerminalViewRemovingStub: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private final class AgentActivityWorkspacePersistenceStub: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
}
