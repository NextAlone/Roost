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

    @Test("returns false for missing pane")
    func missingPane() {
        let appState = makeAppState()
        let updated = appState.updateAgentActivity(paneID: UUID(), state: .completed)
        #expect(updated == false)
    }

    @Test("clears completed agent activity in workspace")
    func clearsCompletedAgentActivityInWorkspace() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        area.activeTab?.content.pane?.activityState = .completed
        appState.workspaceRoots[key] = .tabArea(area)

        let cleared = appState.clearCompletedAgentActivity(for: key)

        #expect(cleared == true)
        #expect(area.activeTab?.content.pane?.activityState == .idle)
    }

    @Test("does not clear running agent activity in workspace")
    func doesNotClearRunningAgentActivityInWorkspace() {
        let appState = makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        area.activeTab?.content.pane?.activityState = .running
        appState.workspaceRoots[key] = .tabArea(area)

        let cleared = appState.clearCompletedAgentActivity(for: key)

        #expect(cleared == false)
        #expect(area.activeTab?.content.pane?.activityState == .running)
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

        appState.dispatch(.selectTab(projectID: projectID, areaID: area.id, tabID: tabID))

        #expect(area.activeTab?.content.pane?.activityState == .idle)
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

        appState.dispatch(.focusArea(projectID: projectID, areaID: area.id))

        #expect(area.activeTab?.content.pane?.activityState == .idle)
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
