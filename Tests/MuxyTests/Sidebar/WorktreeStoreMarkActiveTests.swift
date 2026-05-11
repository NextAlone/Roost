import XCTest
@testable import Roost
@testable import MuxyShared

final class InMemoryWorktreePersistence: WorktreePersisting {
    var storage: [UUID: [Worktree]] = [:]
    func loadWorktrees(projectID: UUID) throws -> [Worktree] { storage[projectID] ?? [] }
    func saveWorktrees(_ list: [Worktree], projectID: UUID) throws { storage[projectID] = list }
    func removeWorktrees(projectID: UUID) throws { storage[projectID] = nil }
}

final class CountingPersistence: WorktreePersisting {
    let inner: any WorktreePersisting
    var saveCount = 0
    init(inner: any WorktreePersisting) { self.inner = inner }
    func loadWorktrees(projectID: UUID) throws -> [Worktree] {
        try inner.loadWorktrees(projectID: projectID)
    }
    func saveWorktrees(_ list: [Worktree], projectID: UUID) throws {
        saveCount += 1
        try inner.saveWorktrees(list, projectID: projectID)
    }
    func removeWorktrees(projectID: UUID) throws {
        try inner.removeWorktrees(projectID: projectID)
    }
}

@MainActor
final class WorktreeStoreMarkActiveTests: XCTestCase {
    func testMarkActiveUpdatesInMemory() async throws {
        let project = Project(name: "p", path: "/tmp/p")
        let persistence = InMemoryWorktreePersistence()
        let primary = Worktree(name: "default", path: "/tmp/p", isPrimary: true)
        try persistence.saveWorktrees([primary], projectID: project.id)
        let store = WorktreeStore(persistence: persistence, projects: [project])

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.markActive(projectID: project.id, worktreeID: primary.id, at: now)

        XCTAssertEqual(store.worktree(projectID: project.id, worktreeID: primary.id)?.lastActiveAt, now)
    }

    func testMarkActivePersistsAfterDebounce() async throws {
        let project = Project(name: "p", path: "/tmp/p")
        let persistence = InMemoryWorktreePersistence()
        let primary = Worktree(name: "default", path: "/tmp/p", isPrimary: true)
        try persistence.saveWorktrees([primary], projectID: project.id)
        let store = WorktreeStore(
            persistence: persistence,
            projects: [project],
            saveDebounce: .milliseconds(10)
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        store.markActive(projectID: project.id, worktreeID: primary.id, at: now)
        try await Task.sleep(for: .milliseconds(30))

        let reloaded = try persistence.loadWorktrees(projectID: project.id)
        XCTAssertEqual(reloaded.first?.lastActiveAt, now)
    }

    func testMarkActiveCollapsesBurstIntoSingleWrite() async throws {
        let project = Project(name: "p", path: "/tmp/p")
        let persistence = CountingPersistence(inner: InMemoryWorktreePersistence())
        let primary = Worktree(name: "default", path: "/tmp/p", isPrimary: true)
        try persistence.saveWorktrees([primary], projectID: project.id)
        persistence.saveCount = 0
        let store = WorktreeStore(
            persistence: persistence,
            projects: [project],
            saveDebounce: .milliseconds(10)
        )

        for i in 0 ..< 5 {
            store.markActive(
                projectID: project.id,
                worktreeID: primary.id,
                at: Date(timeIntervalSince1970: 1_700_000_000 + Double(i))
            )
        }
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(persistence.saveCount, 1)
    }
}
