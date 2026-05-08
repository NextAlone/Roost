import Foundation
import Testing

@testable import RoostHostdCore

private func tmuxAvailable() -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["tmux", "-V"]
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    } catch {
        return false
    }
}

@Suite("HostdTmuxController capture", .enabled(if: tmuxAvailable()))
struct HostdTmuxControllerCaptureTests {
    @Test("paneDead and capture after agent exit")
    func paneDeadAndCaptureAfterAgentExit() async throws {
        let controller = HostdTmuxController()
        let name = "roost-test-cap-\(UUID().uuidString.prefix(8))"
        try await controller.launch(
            sessionName: name,
            workspacePath: "/tmp",
            command: "echo TAIL_MARKER_xyzzy && exit 0",
            environment: [:]
        )
        var dead = false
        for _ in 0..<20 {
            if await controller.isPaneDead(sessionName: name) {
                dead = true
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(dead)
        let tail = await controller.captureLastTail(sessionName: name, lines: 50)
        try? await controller.killSession(named: name)
        #expect(tail?.contains("TAIL_MARKER_xyzzy") == true)
    }
}
