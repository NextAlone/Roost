import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjWorktreeController")
struct JjWorktreeControllerTests {
    @Test("addWorktree without createRef calls workspace add only")
    func addWithoutRef() async throws {
        let calls = JjControllerCallLog()
        let controller = JjWorktreeController(
            workspaceList: { _ in [] },
            workspaceAdd: { _, name, path in
                await calls.append("workspace.add:\(name)@\(path)")
            },
            workspaceForget: { _, _ in },
            bookmarkCreate: { _, _ in
                await calls.append("bookmark.create:should-not-be-called")
            },
            bookmarkForget: { _, _ in }
        )
        try await controller.addWorktree(
            repoPath: "/repo",
            name: "feat-x",
            path: "/repo/.worktrees/feat-x",
            ref: nil,
            createRef: false
        )
        let log = await calls.entries
        #expect(log == ["workspace.add:feat-x@/repo/.worktrees/feat-x"])
    }

    @Test("addWorktree with createRef also creates bookmark")
    func addWithCreateRef() async throws {
        let calls = JjControllerCallLog()
        let controller = JjWorktreeController(
            workspaceList: { _ in [] },
            workspaceAdd: { _, name, path in
                await calls.append("workspace.add:\(name)@\(path)")
            },
            workspaceForget: { _, _ in },
            bookmarkCreate: { _, name in
                await calls.append("bookmark.create:\(name)")
            },
            bookmarkForget: { _, _ in }
        )
        try await controller.addWorktree(
            repoPath: "/repo",
            name: "feat-x",
            path: "/repo/.worktrees/feat-x",
            ref: "feat-x",
            createRef: true
        )
        let log = await calls.entries
        #expect(log == [
            "workspace.add:feat-x@/repo/.worktrees/feat-x",
            "bookmark.create:feat-x"
        ])
    }

    @Test("removeWorktree with explicit identifier calls workspace forget by name + deletes path")
    func removeByIdentifier() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("jjctrl-id-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let calls = JjControllerCallLog()
        let controller = JjWorktreeController(
            workspaceList: { _ in [] },
            workspaceAdd: { _, _, _ in },
            workspaceForget: { _, name in
                await calls.append("workspace.forget:\(name)")
            },
            bookmarkCreate: { _, _ in },
            bookmarkForget: { _, _ in }
        )
        try await controller.removeWorktree(
            repoPath: "/repo",
            path: tmp.path,
            target: .identified("feat-x"),
            force: true
        )

        let log = await calls.entries
        #expect(log == ["workspace.forget:feat-x"])
        #expect(fm.fileExists(atPath: tmp.path) == false)
    }

    @Test("removeWorktree without identifier falls back to leaf-name match")
    func removeByPath() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("jjctrl-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let calls = JjControllerCallLog()
        let leafName = tmp.lastPathComponent
        let entry = JjWorkspaceEntry(
            name: leafName,
            workingCopy: JjChangeId(prefix: "abcdef0123ab", full: "abcdef0123abcdef0123456789abcdef")
        )
        let controller = JjWorktreeController(
            workspaceList: { _ in [entry] },
            workspaceAdd: { _, _, _ in },
            workspaceForget: { _, name in
                await calls.append("workspace.forget:\(name)")
            },
            bookmarkCreate: { _, _ in },
            bookmarkForget: { _, _ in }
        )
        try await controller.removeWorktree(repoPath: "/repo", path: tmp.path, target: .orphan, force: true)

        let log = await calls.entries
        #expect(log == ["workspace.forget:\(leafName)"])
        #expect(fm.fileExists(atPath: tmp.path) == false)
    }

    @Test("removeWorktree tolerates already-deleted path after forget")
    func removeAlreadyMissingPath() async throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("jjctrl-missing-\(UUID().uuidString)")
        let calls = JjControllerCallLog()
        let controller = JjWorktreeController(
            workspaceList: { _ in [] },
            workspaceAdd: { _, _, _ in },
            workspaceForget: { _, name in
                await calls.append("workspace.forget:\(name)")
            },
            bookmarkCreate: { _, _ in },
            bookmarkForget: { _, _ in }
        )
        try await controller.removeWorktree(
            repoPath: "/repo",
            path: tmp.path,
            target: .identified("feat-x"),
            force: true
        )
        let log = await calls.entries
        #expect(log == ["workspace.forget:feat-x"])
        #expect(fm.fileExists(atPath: tmp.path) == false)
    }

    @Test("deleteRef calls bookmark forget")
    func deleteRefCallsBookmarkForget() async throws {
        let calls = JjControllerCallLog()
        let controller = JjWorktreeController(
            workspaceList: { _ in [] },
            workspaceAdd: { _, _, _ in },
            workspaceForget: { _, _ in },
            bookmarkCreate: { _, _ in },
            bookmarkForget: { _, name in
                await calls.append("bookmark.forget:\(name)")
            }
        )
        try await controller.deleteRef(repoPath: "/repo", name: "feat-x")
        let log = await calls.entries
        #expect(log == ["bookmark.forget:feat-x"])
    }
}

actor JjControllerCallLog {
    var entries: [String] = []
    func append(_ s: String) { entries.append(s) }
}
