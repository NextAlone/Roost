import XCTest
@testable import Roost
@testable import MuxyShared

final class ProjectSortingServiceTests: XCTestCase {
    private func project(_ name: String, sortOrder: Int) -> Project {
        var p = Project(name: name, path: "/tmp/\(name)")
        p.sortOrder = sortOrder
        return p
    }

    private func worktree(lastActiveAt: Date?) -> Worktree {
        var w = Worktree(name: "default", path: "/tmp/x", isPrimary: true)
        w.lastActiveAt = lastActiveAt
        return w
    }

    func testManualModePreservesSortOrder() {
        let a = project("a", sortOrder: 2)
        let b = project("b", sortOrder: 0)
        let c = project("c", sortOrder: 1)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sorted = ProjectSortingService.sort(
            projects: [a, b, c],
            worktreesByProject: [:],
            mode: .manual,
            now: now
        )
        XCTAssertEqual(sorted.map(\.name), ["b", "c", "a"])
    }

    func testActiveModePartitionsByFourHourWindow() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = project("a", sortOrder: 2)
        let b = project("b", sortOrder: 0)
        let c = project("c", sortOrder: 1)
        let worktreesByProject: [UUID: [Worktree]] = [
            a.id: [worktree(lastActiveAt: now.addingTimeInterval(-60 * 30))],
            b.id: [worktree(lastActiveAt: now.addingTimeInterval(-60 * 60 * 5))],
            c.id: [worktree(lastActiveAt: now.addingTimeInterval(-60 * 60 * 2))],
        ]
        let sorted = ProjectSortingService.sort(
            projects: [a, b, c],
            worktreesByProject: worktreesByProject,
            mode: .active,
            now: now
        )
        XCTAssertEqual(sorted.map(\.name), ["a", "c", "b"])
    }

    func testActiveModePlacesNilActivityIntoRestByManualOrder() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = project("a", sortOrder: 0)
        let b = project("b", sortOrder: 1)
        let worktreesByProject: [UUID: [Worktree]] = [
            a.id: [worktree(lastActiveAt: nil)],
            b.id: [worktree(lastActiveAt: nil)],
        ]
        let sorted = ProjectSortingService.sort(
            projects: [a, b],
            worktreesByProject: worktreesByProject,
            mode: .active,
            now: now
        )
        XCTAssertEqual(sorted.map(\.name), ["a", "b"])
    }

    func testActiveModeBoundaryExactlyAtThreshold() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let onEdge = project("edge", sortOrder: 5)
        let just = project("just", sortOrder: 0)
        let worktreesByProject: [UUID: [Worktree]] = [
            onEdge.id: [worktree(lastActiveAt: now.addingTimeInterval(-60 * 60 * 4))],
            just.id: [worktree(lastActiveAt: now.addingTimeInterval(-60 * 60 * 4 - 1))],
        ]
        let sorted = ProjectSortingService.sort(
            projects: [onEdge, just],
            worktreesByProject: worktreesByProject,
            mode: .active,
            now: now
        )
        XCTAssertEqual(sorted.map(\.name), ["edge", "just"])
    }
}
