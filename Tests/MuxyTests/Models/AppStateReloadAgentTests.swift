import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("AppState.reloadAgent")
struct AppStateReloadAgentTests {
    @Test("reload terminates by paneID and rotates view sessionID")
    func reloadCallsTerminateThenDispatches() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        let oldSessionID = pane.sessionID
        await app.reloadAgent(paneID: pane.id)
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
        await app.reloadAgent(paneID: pane.id)
        let firstSessionID = pane.sessionID
        let firstTerminateCount = rig.terminateCalls.filter { $0 == pane.id }.count
        await app.reloadAgent(paneID: pane.id)
        #expect(pane.sessionID != firstSessionID)
        let secondTerminateCount = rig.terminateCalls.filter { $0 == pane.id }.count
        #expect(secondTerminateCount == firstTerminateCount * 2)
    }

    @Test("reload preserves preset startupCommand on persist")
    func reloadPreservesPresetCommand() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        let originalCommand = pane.startupCommand
        pane.lastState = .exited
        pane.capturedResumeCommand = "claude --resume abc-123"
        await app.reloadAgent(paneID: pane.id)
        #expect(pane.startupCommand == originalCommand)
        #expect(pane.startupCommand?.contains("--resume") == false)
    }

    @Test("reload runtime command appends --resume id")
    func reloadRuntimeCommandAppendsResume() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        pane.lastState = .exited
        pane.capturedResumeCommand = "claude --resume abc-123"
        await app.reloadAgent(paneID: pane.id)
        try await Task.sleep(nanoseconds: 100_000_000)
        let resumeCreates = rig.createCalls.filter { $0.sessionID == pane.id && ($0.command ?? "").contains("--resume abc-123") }
        #expect(resumeCreates.count == 1)
    }

    @Test("reload sends graceful exit keys for claude")
    func reloadSendsGracefulExitKeys() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        let app = rig.makeAppState()
        let pane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        await app.reloadAgent(paneID: pane.id)
        let claudeExitCalls = rig.sendTmuxKeysCalls.filter { $0.0 == pane.id && $0.1 == ["/exit", "Enter"] }
        #expect(claudeExitCalls.count == 1)
    }

    @Test("concurrent reload is dropped")
    func concurrentReloadIsDropped() async throws {
        let rig = AppStateTestRig()
        rig.ownership = .hostdOwnedProcess
        rig.slowTerminateNanoseconds = 200_000_000
        let app = rig.makeAppState()
        let baselinePane = await rig.makeAgentPane(kind: .claudeCode, app: app)
        let concurrentPane = await rig.makeAgentPane(kind: .claudeCode, app: app)

        await app.reloadAgent(paneID: baselinePane.id)
        let baselineCalls = rig.terminateCalls.filter { $0 == baselinePane.id }.count

        async let first: () = app.reloadAgent(paneID: concurrentPane.id)
        async let second: () = app.reloadAgent(paneID: concurrentPane.id)
        _ = await (first, second)
        let concurrentCalls = rig.terminateCalls.filter { $0 == concurrentPane.id }.count

        #expect(concurrentCalls == baselineCalls)
    }
}
