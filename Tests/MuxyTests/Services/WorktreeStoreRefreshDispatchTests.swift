import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("WorktreeStore refresh dispatch")
struct WorktreeStoreRefreshDispatchTests {
    private let fm = FileManager.default

    private func makeTempDir() -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("ws-dispatch-\(UUID().uuidString)")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("primary .jj routes through jj listing")
    func dispatchesJj() async throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".jj"), withIntermediateDirectories: true)

        let gitCalls = RefreshDispatchCallCounter()
        let jjCalls = RefreshDispatchCallCounter()

        let persistence = RefreshDispatchTestPersistence()
        let store = WorktreeStore(
            persistence: persistence,
            listGitWorktrees: { _ in
                await gitCalls.bump()
                return []
            },
            listJjWorkspaces: { _ in
                await jjCalls.bump()
                return [
                    JjWorkspaceEntry(
                        name: "default",
                        workingCopy: JjChangeId(prefix: "abcdefabcdef", full: "abcdefabcdef0123456789abcdef")
                    )
                ]
            }
        )

        let project = Project(name: "P", path: dir.path, sortOrder: 0)
        store.ensurePrimary(for: project)
        let refreshed = try await store.refresh(project: project)

        #expect(await jjCalls.value == 1)
        #expect(await gitCalls.value == 0)
        #expect(refreshed.first(where: \.isPrimary)?.currentChangeId == "abcdefabcdef0123456789abcdef")
    }

    @Test("primary .git routes through git listing")
    func dispatchesGit() async throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let gitCalls = RefreshDispatchCallCounter()
        let jjCalls = RefreshDispatchCallCounter()

        let persistence = RefreshDispatchTestPersistence()
        let store = WorktreeStore(
            persistence: persistence,
            listGitWorktrees: { _ in
                await gitCalls.bump()
                return []
            },
            listJjWorkspaces: { _ in
                await jjCalls.bump()
                return []
            }
        )

        let project = Project(name: "P", path: dir.path, sortOrder: 0)
        store.ensurePrimary(for: project)
        _ = try await store.refresh(project: project)

        #expect(await gitCalls.value == 1)
        #expect(await jjCalls.value == 0)
    }
}

actor RefreshDispatchCallCounter {
    var value: Int = 0
    func bump() { value += 1 }
}

final class RefreshDispatchTestPersistence: WorktreePersisting, @unchecked Sendable {
    private var stored: [UUID: [Worktree]] = [:]
    func loadWorktrees(projectID: UUID) throws -> [Worktree] { stored[projectID] ?? [] }
    func saveWorktrees(_ worktrees: [Worktree], projectID: UUID) throws { stored[projectID] = worktrees }
    func removeWorktrees(projectID: UUID) throws { stored.removeValue(forKey: projectID) }
}
