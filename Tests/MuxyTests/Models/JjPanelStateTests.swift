import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("JjPanelState")
struct JjPanelStateTests {
    @Test("starts with no snapshot and not loading")
    func initialState() {
        let state = JjPanelState(repoPath: "/tmp/wt")
        #expect(state.snapshot == nil)
        #expect(state.isLoading == false)
        #expect(state.errorMessage == nil)
    }

    @Test("refresh populates snapshot")
    func refreshPopulates() async {
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(change: change, parents: [], description: "x", diffStat: nil)
        let status = JjStatus(workingCopy: change, parent: nil, workingCopySummary: "", entries: [], hasConflicts: false)
        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            changesLoader: { _ in [] }
        )
        let state = JjPanelState(repoPath: "/tmp/wt", loader: loader)
        await state.refresh()
        #expect(state.snapshot?.show.description == "x")
        #expect(state.snapshot?.status.hasConflicts == false)
        #expect(state.isLoading == false)
        #expect(state.errorMessage == nil)
    }

    @Test("refresh on error sets errorMessage and clears loading")
    func refreshError() async {
        struct Boom: Error, CustomStringConvertible { var description: String { "boom" } }
        let loader = JjPanelLoader(
            showLoader: { _ in throw Boom() },
            statusLoader: { _ in fatalError() },
            changesLoader: { _ in fatalError() }
        )
        let state = JjPanelState(repoPath: "/tmp/wt", loader: loader)
        await state.refresh()
        #expect(state.snapshot == nil)
        #expect(state.errorMessage == "boom")
        #expect(state.isLoading == false)
    }
}
