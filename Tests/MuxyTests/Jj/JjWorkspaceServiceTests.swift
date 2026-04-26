import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjWorkspaceService")
struct JjWorkspaceServiceTests {
    @Test("list parses workspace entries")
    func list() async throws {
        let svc = JjWorkspaceService(queue: JjProcessQueue()) { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data("default: abcdef12 (no description set)\n".utf8),
                stderr: ""
            )
        }
        let entries = try await svc.list(repoPath: "/repo")
        #expect(entries.count == 1)
        #expect(entries[0].name == "default")
    }

    @Test("add invokes workspace add")
    func add() async throws {
        let captured = CapturedArgs()
        let svc = JjWorkspaceService(queue: JjProcessQueue()) { repo, cmd, _, _ in
            await captured.set(repo: repo, cmd: cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.add(repoPath: "/repo", name: "feat-x", path: "/repo/.worktrees/feat-x")
        let cmd = await captured.cmd
        #expect(cmd == ["workspace", "add", "--name", "feat-x", "/repo/.worktrees/feat-x"])
    }

    @Test("forget invokes workspace forget")
    func forget() async throws {
        let captured = CapturedArgs()
        let svc = JjWorkspaceService(queue: JjProcessQueue()) { repo, cmd, _, _ in
            await captured.set(repo: repo, cmd: cmd)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.forget(repoPath: "/repo", name: "feat-x")
        let cmd = await captured.cmd
        #expect(cmd == ["workspace", "forget", "feat-x"])
    }
}

actor CapturedArgs {
    var repo: String = ""
    var cmd: [String] = []
    func set(repo: String, cmd: [String]) {
        self.repo = repo
        self.cmd = cmd
    }
}
