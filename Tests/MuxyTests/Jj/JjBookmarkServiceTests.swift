import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjBookmarkService")
struct JjBookmarkServiceTests {
    @Test("list parses bookmarks")
    func list() async throws {
        let svc = JjBookmarkService(queue: JjProcessQueue()) { _, _, _, _ in
            JjProcessResult(
                status: 0,
                stdout: Data("main\t\tus\tuskwmzzuvtuzuqsrzvqwsnyulvmxpmtu\n".utf8),
                stderr: ""
            )
        }
        let bookmarks = try await svc.list(repoPath: "/repo")
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].name == "main")
        #expect(bookmarks[0].isLocal == true)
        #expect(bookmarks[0].target?.full == "uskwmzzuvtuzuqsrzvqwsnyulvmxpmtu")
    }

    @Test("create invokes bookmark create")
    func create() async throws {
        let captured = BookmarkCapturedCall()
        let svc = JjBookmarkService(queue: JjProcessQueue()) { repo, cmd, snapshot, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: snapshot)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.create(repoPath: "/repo", name: "feat-x", revset: nil)
        let cmd = await captured.cmd
        let snapshot = await captured.snapshot
        #expect(cmd == ["bookmark", "create", "feat-x"])
        #expect(snapshot == .allow)
    }

    @Test("create with revset adds -r")
    func createWithRevset() async throws {
        let captured = BookmarkCapturedCall()
        let svc = JjBookmarkService(queue: JjProcessQueue()) { repo, cmd, _, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: .allow)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.create(repoPath: "/repo", name: "feat-x", revset: "@-")
        let cmd = await captured.cmd
        #expect(cmd == ["bookmark", "create", "feat-x", "-r", "@-"])
    }

    @Test("set moves existing bookmark")
    func set() async throws {
        let captured = BookmarkCapturedCall()
        let svc = JjBookmarkService(queue: JjProcessQueue()) { repo, cmd, _, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: .allow)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.setTarget(repoPath: "/repo", name: "main", revset: "@-")
        let cmd = await captured.cmd
        #expect(cmd == ["bookmark", "set", "main", "-r", "@-"])
    }

    @Test("forget deletes bookmark")
    func forget() async throws {
        let captured = BookmarkCapturedCall()
        let svc = JjBookmarkService(queue: JjProcessQueue()) { repo, cmd, _, _ in
            await captured.set(repo: repo, cmd: cmd, snapshot: .allow)
            return JjProcessResult(status: 0, stdout: Data(), stderr: "")
        }
        try await svc.forget(repoPath: "/repo", name: "feat-x")
        let cmd = await captured.cmd
        #expect(cmd == ["bookmark", "forget", "feat-x"])
    }
}

actor BookmarkCapturedCall {
    var repo: String = ""
    var cmd: [String] = []
    var snapshot: JjSnapshotPolicy = .ignore
    func set(repo: String, cmd: [String], snapshot: JjSnapshotPolicy) {
        self.repo = repo
        self.cmd = cmd
        self.snapshot = snapshot
    }
}
