import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("AppState.reloadAgent")
struct AppStateReloadAgentTests {
    @Test("fresh reload terminates by paneID and rotates view sessionID")
    func freshReloadCallsTerminateThenDispatches() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        let oldSessionID = pane.sessionID
        await app.reloadAgent(paneID: pane.id, mode: .fresh)
        #expect(rig.terminateCalls.contains(pane.id))
        #expect(pane.sessionID != oldSessionID)
        #expect(pane.sessionID != pane.id)
        #expect(pane.startupCommand == "claude --dangerously-skip-permissions")
    }

    @Test("second reload still rotates view sessionID")
    func secondReloadRotatesViewSessionID() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        await app.reloadAgent(paneID: pane.id, mode: .fresh)
        let firstSessionID = pane.sessionID
        await app.reloadAgent(paneID: pane.id, mode: .fresh)
        #expect(pane.sessionID != firstSessionID)
        #expect(rig.terminateCalls.filter { $0 == pane.id }.count == 2)
    }

    @Test("resume reload preserves preset startupCommand on persist")
    func resumeReloadPreservesPresetCommand() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        let originalCommand = pane.startupCommand
        pane.lastState = .exited
        pane.capturedResumeCommand = "claude --resume abc-123"
        await app.reloadAgent(paneID: pane.id, mode: .resume)
        #expect(pane.startupCommand == originalCommand)
        #expect(pane.startupCommand?.contains("--resume") == false)
    }

    @Test("resume reload runtime command appends --resume id")
    func resumeReloadRuntimeCommandAppendsResume() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        pane.lastState = .exited
        pane.capturedResumeCommand = "claude --resume abc-123"
        await app.reloadAgent(paneID: pane.id, mode: .resume)
        try await Task.sleep(nanoseconds: 100_000_000)
        let resumeCreates = rig.createCalls.filter { $0.sessionID == pane.id && ($0.command ?? "").contains("--resume abc-123") }
        #expect(resumeCreates.count == 1)
    }

    @Test("resume reload sends graceful exit keys for claude")
    func resumeReloadSendsGracefulExitKeys() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        await app.reloadAgent(paneID: pane.id, mode: .resume)
        let claudeExitCalls = rig.sendTmuxKeysCalls.filter { $0.0 == pane.id && $0.1 == ["/exit", "Enter"] }
        #expect(claudeExitCalls.count == 1)
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
