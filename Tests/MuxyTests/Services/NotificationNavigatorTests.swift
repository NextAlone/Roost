import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("NotificationNavigator")
struct NotificationNavigatorTests {
    @Test("navigate clears completed agent activity in workspace")
    func navigateClearsCompletedAgentActivity() {
        let appState = makeAppState()
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .codex)
        let agentTab = area.activeTab!
        let pane = agentTab.content.pane!
        pane.activityState = .completed
        appState.workspaceRoots[key] = .tabArea(area)
        appState.focusedAreaID[key] = area.id

        let notification = MuxyNotification(
            paneID: pane.id,
            projectID: projectID,
            worktreeID: worktreeID,
            areaID: area.id,
            tabID: agentTab.id,
            worktreePath: "/tmp/wt",
            source: .aiProvider("codex"),
            title: "Codex",
            body: "Done"
        )

        NotificationNavigator.navigate(
            to: notification,
            appState: appState,
            notificationStore: NotificationStore.shared
        )

        #expect(pane.activityState == .idle)
    }

    private func makeAppState() -> AppState {
        AppState(
            selectionStore: NotificationNavigatorSelectionStoreStub(),
            terminalViews: NotificationNavigatorTerminalViewRemovingStub(),
            workspacePersistence: NotificationNavigatorWorkspacePersistenceStub()
        )
    }
}

@MainActor
private final class NotificationNavigatorSelectionStoreStub: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

@MainActor
private final class NotificationNavigatorTerminalViewRemovingStub: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private final class NotificationNavigatorWorkspacePersistenceStub: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
}
