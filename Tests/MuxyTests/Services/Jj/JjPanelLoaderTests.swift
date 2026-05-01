import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("JjPanelLoader")
struct JjPanelLoaderTests {
    @Test("composes show + status + summary + bookmarks + conflicts into a snapshot")
    func composes() async throws {
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(
            change: change,
            parents: [],
            description: "demo",
            diffStat: nil
        )
        let entry = JjStatusEntry(change: .modified, path: "README.md")
        let status = JjStatus(
            workingCopy: change,
            parent: nil,
            workingCopySummary: "",
            entries: [entry],
            hasConflicts: true
        )
        let logEntry = JjLogEntry(
            graphPrefix: "@  ",
            change: change,
            commitId: "abc123",
            isEmpty: false,
            authorName: "A",
            authorTimestamp: "2026-05-01T00:00:00+08:00",
            description: "demo"
        )
        let bookmark = JjBookmark(name: "main", target: change, isLocal: true, remotes: [])
        let conflict = JjConflict(path: "README.md")
        let operation = JjOperation(
            id: "abc1234",
            timestamp: Date(timeIntervalSince1970: 1_776_000_000),
            description: "commit"
        )

        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            changesLoader: { _ in [logEntry] },
            bookmarksLoader: { _ in [bookmark] },
            conflictsLoader: { _ in [conflict] },
            operationsLoader: { _ in [operation] }
        )
        let snapshot = try await loader.load(repoPath: "/tmp/wt")
        #expect(snapshot.show.description == "demo")
        #expect(snapshot.status.entries.count == 1)
        #expect(snapshot.changes.count == 1)
        #expect(snapshot.bookmarks.count == 1)
        #expect(snapshot.conflicts.first?.path == "README.md")
        #expect(snapshot.operations.first?.id == "abc1234")
    }

    @Test("conflicts not fetched when status.hasConflicts == false")
    func skipsConflictsWhenClean() async throws {
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(change: change, parents: [], description: "x", diffStat: nil)
        let status = JjStatus(workingCopy: change, parent: nil, workingCopySummary: "", entries: [], hasConflicts: false)
        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            changesLoader: { _ in [] },
            bookmarksLoader: { _ in [] },
            conflictsLoader: { _ in fatalError("must not be called") },
            operationsLoader: { _ in [] }
        )
        let snapshot = try await loader.load(repoPath: "/tmp/wt")
        #expect(snapshot.conflicts.isEmpty)
    }

    @Test("empty working copy keeps file list empty")
    func emptyWorkingCopyKeepsFileListEmpty() async throws {
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(change: change, parents: [], description: "x", diffStat: nil)
        let status = JjStatus(workingCopy: change, parent: nil, workingCopySummary: "", entries: [], hasConflicts: false)
        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            changesLoader: { _ in [] },
            bookmarksLoader: { _ in [] },
            operationsLoader: { _ in [] }
        )
        let snapshot = try await loader.load(repoPath: "/tmp/wt")
        #expect(snapshot.status.entries.isEmpty)
    }

    @Test("propagates show errors")
    func propagatesShowError() async {
        struct Boom: Error {}
        let loader = JjPanelLoader(
            showLoader: { _ in throw Boom() },
            statusLoader: { _ in fatalError("not reached") },
            changesLoader: { _ in fatalError("not reached") },
            bookmarksLoader: { _ in fatalError("not reached") },
            conflictsLoader: { _ in fatalError("not reached") }
        )
        await #expect(throws: Boom.self) {
            try await loader.load(repoPath: "/tmp/wt")
        }
    }
}
