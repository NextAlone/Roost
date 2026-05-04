import Foundation
import Testing

@testable import Roost

@MainActor
@Suite("AppState layout apply")
struct AppStateLayoutApplyTests {
    @Test("requestApplyLayout blocks unsaved editor tabs")
    func requestApplyLayoutBlocksUnsavedEditorTabs() {
        let projectID = UUID()
        let worktreeID = UUID()
        let appState = makeAppState(projectID: projectID, worktreeID: worktreeID)
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        area.createEditorTab(filePath: "/tmp/wt/file.swift")
        area.activeTab?.content.editorState?.isModified = true
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id

        appState.requestApplyLayout(projectID: projectID, layoutName: "dev")

        #expect(appState.pendingLayoutApply == nil)
        #expect(appState.pendingLayoutApplyBlockedMessage?.contains("Save or close") == true)
    }

    @Test("requestApplyLayout blocks running process tabs while close confirmation is enabled")
    func requestApplyLayoutBlocksRunningProcesses() {
        let previous = TabCloseConfirmationPreferences.confirmRunningProcess
        TabCloseConfirmationPreferences.confirmRunningProcess = true
        defer { TabCloseConfirmationPreferences.confirmRunningProcess = previous }

        let projectID = UUID()
        let worktreeID = UUID()
        let terminalViews = LayoutApplyTerminalViewRemovingStub()
        let appState = makeAppState(
            projectID: projectID,
            worktreeID: worktreeID,
            terminalViews: terminalViews
        )
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        let paneID = area.activeTab!.content.pane!.id
        terminalViews.paneIDsNeedingConfirmation = [paneID]
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id

        appState.requestApplyLayout(projectID: projectID, layoutName: "dev")

        #expect(appState.pendingLayoutApply == nil)
        #expect(appState.pendingLayoutApplyBlockedMessage?.contains("running process") == true)
    }

    private func makeAppState(
        projectID: UUID,
        worktreeID: UUID,
        terminalViews: LayoutApplyTerminalViewRemovingStub = LayoutApplyTerminalViewRemovingStub()
    ) -> AppState {
        let appState = AppState(
            selectionStore: LayoutApplySelectionStoreStub(),
            terminalViews: terminalViews,
            workspacePersistence: LayoutApplyWorkspacePersistenceStub()
        )
        appState.activeProjectID = projectID
        appState.activeWorktreeID[projectID] = worktreeID
        return appState
    }
}

@MainActor
private final class LayoutApplySelectionStoreStub: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_: [UUID: UUID]) {}
}

@MainActor
private final class LayoutApplyTerminalViewRemovingStub: TerminalViewRemoving {
    var paneIDsNeedingConfirmation: Set<UUID> = []
    func removeView(for _: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool {
        paneIDsNeedingConfirmation.contains(paneID)
    }
}

private final class LayoutApplyWorkspacePersistenceStub: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_: [WorkspaceSnapshot]) throws {}
}
