import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("JjPanelLoader")
struct JjPanelLoaderTests {
    @Test("composes show + status + summary into a snapshot")
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
            hasConflicts: false
        )
        let parentDiff = [entry]

        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            summaryLoader: { _, _ in parentDiff }
        )
        let snapshot = try await loader.load(repoPath: "/tmp/wt")
        #expect(snapshot.show.description == "demo")
        #expect(snapshot.parentDiff.count == 1)
        #expect(snapshot.status.entries.count == 1)
    }

    @Test("propagates show errors")
    func propagatesShowError() async {
        struct Boom: Error {}
        let loader = JjPanelLoader(
            showLoader: { _ in throw Boom() },
            statusLoader: { _ in fatalError("not reached") },
            summaryLoader: { _, _ in fatalError("not reached") }
        )
        await #expect(throws: Boom.self) {
            try await loader.load(repoPath: "/tmp/wt")
        }
    }
}
