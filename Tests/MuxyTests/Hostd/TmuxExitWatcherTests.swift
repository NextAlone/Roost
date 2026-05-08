import Foundation
@testable import RoostHostdCore
import Testing

@Suite("Tmux exit watcher")
struct TmuxExitWatcherTests {
    final class MockTmux: HostdTmuxControlling, @unchecked Sendable {
        var hasSessionResults: [Bool]
        var paneDeadResults: [Bool]
        var lastTailValue: String?
        var killCount = 0

        init(hasSession: [Bool], paneDead: [Bool], lastTail: String?) {
            self.hasSessionResults = hasSession
            self.paneDeadResults = paneDead
            self.lastTailValue = lastTail
        }

        func launch(sessionName: String, workspacePath: String, command: String, environment: [String: String]) async throws {}
        func hasSession(named sessionName: String) async -> Bool {
            hasSessionResults.isEmpty ? false : hasSessionResults.removeFirst()
        }
        func killSession(named sessionName: String) async throws { killCount += 1 }
        func isPaneDead(sessionName: String) async -> Bool {
            paneDeadResults.isEmpty ? false : paneDeadResults.removeFirst()
        }
        func captureLastTail(sessionName: String, lines: Int) async -> String? { lastTailValue }
        func sendKeys(sessionName: String, keys: String) async throws {}
    }

    final class ExitCapture: @unchecked Sendable {
        var lastTail: String?
        var exited = false

        init(initialLastTail: String? = nil) {
            lastTail = initialLastTail
        }
    }

    @Test("reports exit with captured tail")
    func reportsExitWithCapturedTail() async {
        let mock = MockTmux(
            hasSession: [true, true, true],
            paneDead: [false, false, true],
            lastTail: "TAIL_MARKER"
        )
        let capture = ExitCapture()
        await HostdProcessRegistry.runTmuxExitWatcherLoop(
            sessionName: "roost-X",
            tmux: mock,
            pollNanoseconds: 50_000_000
        ) { tail in
            capture.lastTail = tail
            capture.exited = true
        }
        #expect(capture.exited)
        #expect(capture.lastTail == "TAIL_MARKER")
        #expect(mock.killCount == 1)
    }

    @Test("session lost reports nil tail")
    func sessionLostReportsNilTail() async {
        let mock = MockTmux(
            hasSession: [false],
            paneDead: [],
            lastTail: nil
        )
        let capture = ExitCapture(initialLastTail: "not-changed")
        await HostdProcessRegistry.runTmuxExitWatcherLoop(
            sessionName: "roost-X",
            tmux: mock,
            pollNanoseconds: 50_000_000
        ) { tail in
            capture.lastTail = tail
            capture.exited = true
        }
        #expect(capture.exited)
        #expect(capture.lastTail == nil)
        #expect(mock.killCount == 0)
    }
}
