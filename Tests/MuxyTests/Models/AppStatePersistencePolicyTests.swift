import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("AppState persistence policy")
struct AppStatePersistencePolicyTests {
    @Test("selecting an existing project does not synchronously save workspace snapshots")
    func selectingExistingProjectDoesNotSaveWorkspaceSnapshots() {
        let persistence = CountingWorkspacePersistence()
        let appState = makeAppState(persistence: persistence)
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/repo")
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id

        appState.dispatch(.selectProject(projectID: projectID, worktreeID: worktreeID, worktreePath: "/tmp/repo"))

        #expect(persistence.saveCount == 0)
    }

    @Test("selecting a new project persists the created workspace")
    func selectingNewProjectPersistsCreatedWorkspace() {
        let persistence = CountingWorkspacePersistence()
        let appState = makeAppState(persistence: persistence)
        let projectID = UUID()
        let worktreeID = UUID()

        appState.dispatch(.selectProject(projectID: projectID, worktreeID: worktreeID, worktreePath: "/tmp/repo"))

        #expect(persistence.saveCount == 1)
    }

    @Test("selecting a tab does not synchronously save workspace snapshots")
    func selectingTabDoesNotSaveWorkspaceSnapshots() {
        let persistence = CountingWorkspacePersistence()
        let appState = makeAppState(persistence: persistence)
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/repo")
        area.createTab()
        let targetTabID = area.tabs[0].id
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id

        appState.dispatch(.selectTab(projectID: projectID, areaID: area.id, tabID: targetTabID))

        #expect(persistence.saveCount == 0)
    }

    @Test("creating a tab still persists workspace snapshots")
    func creatingTabPersistsWorkspaceSnapshots() {
        let persistence = CountingWorkspacePersistence()
        let appState = makeAppState(persistence: persistence)
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/repo")
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id

        appState.dispatch(.createTab(projectID: projectID, areaID: area.id))

        #expect(persistence.saveCount == 1)
    }

    private func makeAppState(persistence: CountingWorkspacePersistence) -> AppState {
        AppState(
            selectionStore: PersistencePolicySelectionStore(),
            terminalViews: PersistencePolicyTerminalViewRemoving(),
            workspacePersistence: persistence
        )
    }
}

@MainActor
private final class PersistencePolicySelectionStore: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

@MainActor
private final class PersistencePolicyTerminalViewRemoving: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private final class CountingWorkspacePersistence: WorkspacePersisting {
    private(set) var saveCount = 0

    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }

    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {
        saveCount += 1
    }
}
