import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjDiffService")
struct JjDiffServiceTests {
    @Test("stat parses --stat output")
    func stat() async throws {
        let svc = JjDiffService { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data("docs/new.md | 4 ++--\n1 file changed, 2 insertions(+), 2 deletions(-)\n".utf8),
                stderr: ""
            )
        }
        let stat = try await svc.stat(repoPath: "/repo", revset: "@")
        #expect(stat.files.count == 1)
        #expect(stat.files[0].path == "docs/new.md")
        #expect(stat.totalAdditions == 2)
    }

    @Test("summary uses --summary and reuses status entry parser")
    func summary() async throws {
        let svc = JjDiffService { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data("A docs/new.md\nM Muxy/Foo.swift\n".utf8),
                stderr: ""
            )
        }
        let entries = try await svc.summary(repoPath: "/repo", revset: "@")
        #expect(entries.count == 2)
        #expect(entries[0] == JjStatusEntry(change: .added, path: "docs/new.md"))
        #expect(entries[1] == JjStatusEntry(change: .modified, path: "Muxy/Foo.swift"))
    }

    @Test("stat invokes correct command")
    func statCommand() async throws {
        let captured = DiffCapturedCall()
        let svc = JjDiffService { repo, cmd, snapshot, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: snapshot)
            return JjProcessResult(status: 0, stdout: Data("0 files changed, 0 insertions(+), 0 deletions(-)\n".utf8), stderr: "")
        }
        _ = try await svc.stat(repoPath: "/repo", revset: "@-")
        let cmd = await captured.cmd
        let snapshot = await captured.snapshot
        #expect(cmd == ["diff", "--stat", "-r", "@-"])
        #expect(snapshot == .ignore)
    }

    @Test("summary invokes correct command")
    func summaryCommand() async throws {
        let captured = DiffCapturedCall()
        let svc = JjDiffService { repo, cmd, snapshot, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: snapshot)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        _ = try await svc.summary(repoPath: "/repo", revset: "@")
        let cmd = await captured.cmd
        let snapshot = await captured.snapshot
        #expect(cmd == ["diff", "--summary", "-r", "@"])
        #expect(snapshot == .ignore)
    }
}

actor DiffCapturedCall {
    var repo: String = ""
    var cmd: [String] = []
    var snapshot: JjSnapshotPolicy = .ignore
    func set(repo: String, cmd: [String], snapshot: JjSnapshotPolicy) {
        self.repo = repo
        self.cmd = cmd
        self.snapshot = snapshot
    }
}
