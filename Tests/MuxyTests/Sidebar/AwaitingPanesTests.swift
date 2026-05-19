import XCTest
@testable import Roost
@testable import MuxyShared

@MainActor
final class AwaitingPanesTests: XCTestCase {
    func testUpdateAgentActivityBumpsWorktreeLastActiveAt() throws {
        let project = Project(name: "p", path: "/tmp/p")
        let persistence = InMemoryWorktreePersistence()
        let primary = Worktree(name: "default", path: "/tmp/p", isPrimary: true)
        try persistence.saveWorktrees([primary], projectID: project.id)
        let store = WorktreeStore(persistence: persistence, projects: [project])

        let appState = AppState(
            selectionStore: AwaitingPanesSelectionStoreStub(),
            terminalViews: AwaitingPanesTerminalViewRemovingStub(),
            workspacePersistence: AwaitingPanesWorkspacePersistenceStub(),
            activityLog: AwaitingPanesActivityLogStub()
        )
        appState.worktreeStore = store

        let key = WorktreeKey(projectID: project.id, worktreeID: primary.id)
        let area = TabArea(projectPath: primary.path)
        area.createAgentTab(kind: .codex)
        let paneID = area.activeTab!.content.pane!.id
        appState.workspaceRoots[key] = .tabArea(area)

        let before = Date()
        let updated = appState.updateAgentActivity(paneID: paneID, state: .awaiting)
        let after = Date()

        XCTAssertTrue(updated)
        let stamp = store.worktree(projectID: project.id, worktreeID: primary.id)?.lastActiveAt
        XCTAssertNotNil(stamp)
        XCTAssertGreaterThanOrEqual(stamp!, before)
        XCTAssertLessThanOrEqual(stamp!, after)
    }

    func testAgentAttentionPanesReflectsNeedInputWaitAndDoneStates() throws {
        let project = Project(name: "p", path: "/tmp/p")
        let persistence = InMemoryWorktreePersistence()
        let primary = Worktree(name: "default", path: "/tmp/p", isPrimary: true)
        try persistence.saveWorktrees([primary], projectID: project.id)
        let store = WorktreeStore(persistence: persistence, projects: [project])

        let appState = AppState(
            selectionStore: AwaitingPanesSelectionStoreStub(),
            terminalViews: AwaitingPanesTerminalViewRemovingStub(),
            workspacePersistence: AwaitingPanesWorkspacePersistenceStub(),
            activityLog: AwaitingPanesActivityLogStub()
        )
        appState.worktreeStore = store

        let key = WorktreeKey(projectID: project.id, worktreeID: primary.id)
        let area = TabArea(projectPath: primary.path)
        area.createAgentTab(kind: .codex)
        let needInputPane = area.activeTab!.content.pane!
        area.createAgentTab(kind: .codex)
        let waitPane = area.activeTab!.content.pane!
        area.createAgentTab(kind: .codex)
        let donePane = area.activeTab!.content.pane!
        area.createAgentTab(kind: .codex)
        let runningPane = area.activeTab!.content.pane!
        appState.workspaceRoots[key] = .tabArea(area)

        needInputPane.activityState = .running
        _ = appState.updateAgentActivity(paneID: needInputPane.id, state: .awaiting)
        _ = appState.updateAgentActivity(paneID: waitPane.id, state: .awaiting)
        donePane.activityState = .running
        _ = appState.updateAgentActivity(paneID: donePane.id, state: .completed)
        _ = appState.updateAgentActivity(paneID: runningPane.id, state: .running)

        XCTAssertEqual(appState.agentAttentionPanes.map(\.paneID), [needInputPane.id, waitPane.id, donePane.id])
        XCTAssertEqual(appState.agentAttentionPanes.map(\.attentionKind), [.needInput, .wait, .done])

        _ = appState.acknowledgeAgentActivity(paneID: needInputPane.id)
        XCTAssertEqual(appState.agentAttentionPanes.map(\.paneID), [waitPane.id, donePane.id])
    }

    func testAttentionSummaryTextGroupsNeedInputWaitAndDone() {
        XCTAssertEqual(
            PendingAgentsBanner.summaryText(for: [.needInput, .needInput, .wait, .done]),
            "2 need input · 1 waiting · 1 done"
        )
    }
}

@MainActor
private final class AwaitingPanesSelectionStoreStub: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_ id: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_ ids: [UUID: UUID]) {}
}

@MainActor
private final class AwaitingPanesTerminalViewRemovingStub: TerminalViewRemoving {
    func removeView(for paneID: UUID) {}
    func needsConfirmQuit(for paneID: UUID) -> Bool { false }
}

private final class AwaitingPanesWorkspacePersistenceStub: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_ workspaces: [WorkspaceSnapshot]) throws {}
}

@MainActor
private final class AwaitingPanesActivityLogStub: ActivityLogStoring {
    func append(_ event: AgentActivityEvent) {}
}
