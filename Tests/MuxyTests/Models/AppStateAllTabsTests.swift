import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("AppState.allTabs(forKey:)")
struct AppStateAllTabsTests {
    @Test("returns empty for missing key")
    func missingKey() {
        let appState = AppState(
            selectionStore: AllTabsSelectionStoreStub(),
            terminalViews: AllTabsTerminalViewRemovingStub(),
            workspacePersistence: AllTabsWorkspacePersistenceStub()
        )
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        #expect(appState.allTabs(forKey: key).isEmpty)
    }

    @Test("returns flat list across all areas")
    func flatList() {
        let projectID = UUID()
        let worktreeID = UUID()
        let key = WorktreeKey(projectID: projectID, worktreeID: worktreeID)
        let appState = AppState(
            selectionStore: AllTabsSelectionStoreStub(),
            terminalViews: AllTabsTerminalViewRemovingStub(),
            workspacePersistence: AllTabsWorkspacePersistenceStub()
        )
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        area.createAgentTab(kind: .codex)
        appState.workspaceRoots[key] = .tabArea(area)
        let tabs = appState.allTabs(forKey: key)
        #expect(tabs.count == 3)
        #expect(tabs.contains { $0.content.pane?.agentKind == .claudeCode })
        #expect(tabs.contains { $0.content.pane?.agentKind == .codex })
    }
}

@MainActor
private final class AllTabsSelectionStoreStub: ActiveProjectSelectionStoring {
    private var activeProjectID: UUID?
    private var activeWorktreeIDs: [UUID: UUID] = [:]
    func loadActiveProjectID() -> UUID? { activeProjectID }
    func saveActiveProjectID(_ id: UUID?) { activeProjectID = id }
    func loadActiveWorktreeIDs() -> [UUID: UUID] { activeWorktreeIDs }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) { activeWorktreeIDs = ids }
}

@MainActor
private final class AllTabsTerminalViewRemovingStub: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private final class AllTabsWorkspacePersistenceStub: WorkspacePersisting {
    private var snapshots: [WorkspaceSnapshot] = []
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { snapshots }
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws { snapshots = workspaces }
}
