import Foundation
import MuxyShared
import Testing

@testable import Roost

@MainActor
@Suite("JjPanelState")
struct JjPanelStateTests {
    private final class RevsetRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String?] = []

        func record(_ value: String?) {
            lock.lock()
            defer { lock.unlock() }
            values.append(value)
        }

        func snapshot() -> [String?] {
            lock.lock()
            defer { lock.unlock() }
            return values
        }
    }

    @Test("starts with no snapshot and not loading")
    func initialState() {
        let state = JjPanelState(repoPath: "/tmp/wt")
        #expect(state.snapshot == nil)
        #expect(state.isLoading == false)
        #expect(state.errorMessage == nil)
        #expect(state.activeChangesRevset == "")
        #expect(state.changesRevsetPreset == .default)
    }

    @Test("changes preset revsets are stable")
    func changesPresetRevsets() {
        #expect(JjChangesRevsetPreset.menuPresets == [.default, .currentStack, .bookmarks, .all, .conflicts])
        #expect(JjChangesRevsetPreset.default.revset == nil)
        #expect(JjChangesRevsetPreset.currentStack.revset == "::@ & mutable()")
        #expect(JjChangesRevsetPreset.bookmarks.revset == "bookmarks()")
        #expect(JjChangesRevsetPreset.all.revset == "all()")
        #expect(JjChangesRevsetPreset.conflicts.revset == "conflicts()")
        #expect(JjChangesRevsetPreset.custom.canApply == false)
    }

    @Test("change graph filter revsets are stable")
    func changeGraphFilterRevsets() {
        #expect(JjChangeGraphFilter.ancestors.revset(for: "abc123") == "::abc123")
        #expect(JjChangeGraphFilter.descendants.revset(for: "abc123") == "abc123::")
        #expect(JjChangeGraphFilter.around.revset(for: "abc123") == "::abc123 | abc123::")
        #expect(JjChangeGraphFilter.mutableStack.revset(for: "abc123") == "reachable(abc123, mutable())")
    }

    @Test("refresh populates snapshot")
    func refreshPopulates() async {
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(change: change, parents: [], description: "x", diffStat: nil)
        let status = JjStatus(workingCopy: change, parent: nil, workingCopySummary: "", entries: [], hasConflicts: false)
        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            changesLoader: { _, _ in [] }
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
            changesLoader: { _, _ in fatalError() }
        )
        let state = JjPanelState(repoPath: "/tmp/wt", loader: loader)
        await state.refresh()
        #expect(state.snapshot == nil)
        #expect(state.errorMessage == "boom")
        #expect(state.isLoading == false)
    }

    @Test("apply changes revset trims and refreshes")
    func applyChangesRevset() async {
        let recorder = RevsetRecorder()
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(change: change, parents: [], description: "x", diffStat: nil)
        let status = JjStatus(workingCopy: change, parent: nil, workingCopySummary: "", entries: [], hasConflicts: false)
        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            changesLoader: { _, revset in
                recorder.record(revset)
                return []
            },
            bookmarksLoader: { _ in [] },
            operationsLoader: { _ in [] }
        )
        let state = JjPanelState(repoPath: "/tmp/wt", loader: loader)
        await state.applyChangesRevset("  ancestors(@)  ")

        #expect(state.activeChangesRevset == "ancestors(@)")
        #expect(state.changesRevsetPreset == .custom)
        #expect(recorder.snapshot() == ["ancestors(@)"])
    }

    @Test("apply changes preset uses preset revset and refreshes")
    func applyChangesRevsetPreset() async {
        let recorder = RevsetRecorder()
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(change: change, parents: [], description: "x", diffStat: nil)
        let status = JjStatus(workingCopy: change, parent: nil, workingCopySummary: "", entries: [], hasConflicts: false)
        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            changesLoader: { _, revset in
                recorder.record(revset)
                return []
            },
            bookmarksLoader: { _ in [] },
            operationsLoader: { _ in [] }
        )
        let state = JjPanelState(repoPath: "/tmp/wt", loader: loader)
        await state.applyChangesRevsetPreset(.currentStack)

        #expect(state.activeChangesRevset == "::@ & mutable()")
        #expect(state.changesRevsetPreset == .currentStack)
        #expect(recorder.snapshot() == ["::@ & mutable()"])
    }

    @Test("apply change graph filter uses target revset and refreshes")
    func applyChangeGraphFilter() async {
        let recorder = RevsetRecorder()
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(change: change, parents: [], description: "x", diffStat: nil)
        let status = JjStatus(workingCopy: change, parent: nil, workingCopySummary: "", entries: [], hasConflicts: false)
        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            changesLoader: { _, revset in
                recorder.record(revset)
                return []
            },
            bookmarksLoader: { _ in [] },
            operationsLoader: { _ in [] }
        )
        let state = JjPanelState(repoPath: "/tmp/wt", loader: loader)
        await state.applyChangeGraphFilter(.around, targetRevset: "abc123")

        #expect(state.activeChangesRevset == "::abc123 | abc123::")
        #expect(state.changesRevsetPreset == .custom)
        #expect(recorder.snapshot() == ["::abc123 | abc123::"])
    }

    @Test("reset changes revset refreshes default graph")
    func resetChangesRevset() async {
        let recorder = RevsetRecorder()
        let change = JjChangeId(prefix: "ab", full: "abcdef")
        let show = JjShowOutput(change: change, parents: [], description: "x", diffStat: nil)
        let status = JjStatus(workingCopy: change, parent: nil, workingCopySummary: "", entries: [], hasConflicts: false)
        let loader = JjPanelLoader(
            showLoader: { _ in show },
            statusLoader: { _ in status },
            changesLoader: { _, revset in
                recorder.record(revset)
                return []
            },
            bookmarksLoader: { _ in [] },
            operationsLoader: { _ in [] }
        )
        let state = JjPanelState(repoPath: "/tmp/wt", loader: loader)
        await state.applyChangesRevset("ancestors(@)")
        await state.resetChangesRevset()

        #expect(state.activeChangesRevset == "")
        #expect(state.changesRevsetPreset == .default)
        #expect(recorder.snapshot() == ["ancestors(@)", nil])
    }
}
