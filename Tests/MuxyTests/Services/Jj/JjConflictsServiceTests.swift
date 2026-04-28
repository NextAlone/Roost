import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("JjConflictsService")
struct JjConflictsServiceTests {
    @Test("parses 'jj resolve --list' output into conflicts")
    func parses() async throws {
        let stdout = "Cargo.toml    2-sided conflict\nREADME.md    2-sided conflict\n"
        let runner: JjRunFn = { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data(stdout.utf8),
                stderr: ""
            )
        }
        let service = JjConflictsService(queue: JjProcessQueue.shared, runner: runner)
        let conflicts = try await service.list(repoPath: "/tmp/wt")
        #expect(conflicts.map(\.path) == ["Cargo.toml", "README.md"])
    }

    @Test("non-zero exit throws")
    func nonZeroExit() async {
        let runner: JjRunFn = { _, _, _, _ in
            JjProcessResult(status: 1, stdout: Data(), stderr: "boom")
        }
        let service = JjConflictsService(queue: JjProcessQueue.shared, runner: runner)
        await #expect(throws: (any Error).self) {
            _ = try await service.list(repoPath: "/tmp/wt")
        }
    }

    @Test("empty stdout → empty list")
    func emptyOutput() async throws {
        let runner: JjRunFn = { _, _, _, _ in
            JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        let service = JjConflictsService(queue: JjProcessQueue.shared, runner: runner)
        let conflicts = try await service.list(repoPath: "/tmp/wt")
        #expect(conflicts.isEmpty)
    }
}
