import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("AppState.reloadAgent")
struct AppStateReloadAgentTests {
    @Test("fresh reload calls terminate then dispatches reload action")
    func freshReloadCallsTerminateThenDispatches() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        let oldSessionID = pane.sessionID
        await app.reloadAgent(paneID: pane.id, mode: .fresh)
        #expect(rig.terminateCalls.contains(oldSessionID))
        #expect(pane.sessionID != oldSessionID)
        #expect(pane.startupCommand == "claude --dangerously-skip-permissions")
    }

    @Test("resume reload appends resume args")
    func resumeReloadAppendsResumeArgs() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        pane.lastState = .exited
        pane.capturedResumeCommand = "claude --resume abc-123"
        await app.reloadAgent(paneID: pane.id, mode: .resume)
        #expect(pane.startupCommand?.contains("--resume abc-123") == true)
    }

    @Test("concurrent reload is dropped")
    func concurrentReloadIsDropped() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        rig.slowTerminateNanoseconds = 200_000_000
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        async let first: () = app.reloadAgent(paneID: pane.id, mode: .fresh)
        async let second: () = app.reloadAgent(paneID: pane.id, mode: .fresh)
        _ = await (first, second)
        #expect(rig.terminateCalls.count == 1)
    }
}
