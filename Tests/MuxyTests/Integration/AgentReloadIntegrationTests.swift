import Foundation
@testable import Roost
@testable import RoostHostdCore
@testable import MuxyShared
import Testing

private func tmuxAvailable() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["tmux", "-V"]
    p.standardOutput = Pipe()
    p.standardError = Pipe()
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
}

@Suite("Agent reload tmux capture flow", .enabled(if: tmuxAvailable()))
struct AgentReloadIntegrationTests {
    @Test("tmux watcher captures resume hint after fake agent exit")
    func tmuxWatcherCapturesResumeHintAfterFakeAgentExit() async throws {
        let controller = HostdTmuxController()
        let sessionName = "roost-int-\(UUID().uuidString.prefix(8))"
        let resumeLine = "claude --resume int-test-789"
        try await controller.launch(
            sessionName: sessionName,
            workspacePath: "/tmp",
            command: "echo '\(resumeLine)' && exit 0",
            environment: [:]
        )

        var dead = false
        for _ in 0..<30 {
            if await controller.isPaneDead(sessionName: sessionName) { dead = true; break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(dead)

        let tail = await controller.captureLastTail(sessionName: sessionName, lines: 200)
        try? await controller.killSession(named: sessionName)

        #expect(tail != nil)
        #expect(tail?.contains(resumeLine) == true)

        let regex = try NSRegularExpression(pattern: AgentKind.claudeCode.defaultResumeRegex!)
        let range = NSRange(tail!.startIndex..., in: tail!)
        let match = regex.firstMatch(in: tail!, range: range)
        #expect(match != nil)
        if let match, let r = Range(match.range, in: tail!) {
            let captured = String(tail![r]).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(captured == resumeLine)
        }
    }

    @Test("AgentReloadCommandBuilder integrates extracted resume into reload command")
    func reloadCommandBuilderIntegratesExtractedResume() async {
        let preset = AgentPreset(
            kind: .claudeCode,
            defaultCommand: "claude --dangerously-skip-permissions"
        )
        let captured = "claude --resume real-id-456"
        let command = AgentReloadCommandBuilder.build(
            preset: preset,
            captured: captured
        )
        #expect(command == "claude --dangerously-skip-permissions --resume real-id-456")
    }
}
