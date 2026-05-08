import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("AppState.handleSessionExit")
struct AppStateHandleSessionExitTests {
    @Test("captures resume command from matching tail")
    func capturesResumeFromMatchingTail() {
        let rig = AppStateTestRig()
        let app = rig.makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        let pane = area.activeTab!.content.pane!
        app.workspaceRoots[key] = .tabArea(area)

        app.handleSessionExit(
            paneID: pane.id,
            sessionID: pane.sessionID,
            lastTail: "session continuing\nclaude --resume abc-123\n"
        )

        #expect(pane.capturedResumeCommand == "claude --resume abc-123")
        #expect(pane.lastState == .exited)
    }

    @Test("clears captured when tail has no match")
    func noMatchClearsCaptured() {
        let rig = AppStateTestRig()
        let app = rig.makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        let pane = area.activeTab!.content.pane!
        pane.capturedResumeCommand = "stale"
        app.workspaceRoots[key] = .tabArea(area)

        app.handleSessionExit(
            paneID: pane.id,
            sessionID: pane.sessionID,
            lastTail: "boring output"
        )

        #expect(pane.capturedResumeCommand == nil)
        #expect(pane.lastState == .exited)
    }

    @Test("ignores stale sessionID")
    func ignoresStaleSessionID() {
        let rig = AppStateTestRig()
        let app = rig.makeAppState()
        let key = WorktreeKey(projectID: UUID(), worktreeID: UUID())
        let area = TabArea(projectPath: "/tmp/wt")
        area.createAgentTab(kind: .claudeCode)
        let pane = area.activeTab!.content.pane!
        let initialState = pane.lastState
        app.workspaceRoots[key] = .tabArea(area)

        app.handleSessionExit(
            paneID: pane.id,
            sessionID: UUID(),
            lastTail: "claude --resume xyz\n"
        )

        #expect(pane.capturedResumeCommand == nil)
        #expect(pane.lastState == initialState)
    }
}
