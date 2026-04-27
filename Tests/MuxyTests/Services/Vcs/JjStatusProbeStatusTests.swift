import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("JjStatusProbe.status")
struct JjStatusProbeStatusTests {
    @Test("clean when entries empty and no conflicts")
    func cleanCase() async {
        let probe = JjStatusProbe(statusJson: { _ in
            .success(hasEntries: false, hasConflicts: false)
        })
        #expect(await probe.status(at: "/tmp/wt") == .clean)
    }

    @Test("dirty when entries non-empty")
    func dirtyCase() async {
        let probe = JjStatusProbe(statusJson: { _ in
            .success(hasEntries: true, hasConflicts: false)
        })
        #expect(await probe.status(at: "/tmp/wt") == .dirty)
    }

    @Test("conflicted dominates even with empty entries")
    func conflictedDominates() async {
        let probe = JjStatusProbe(statusJson: { _ in
            .success(hasEntries: false, hasConflicts: true)
        })
        #expect(await probe.status(at: "/tmp/wt") == .conflicted)
    }

    @Test("conflicted with entries → conflicted")
    func conflictedWithEntries() async {
        let probe = JjStatusProbe(statusJson: { _ in
            .success(hasEntries: true, hasConflicts: true)
        })
        #expect(await probe.status(at: "/tmp/wt") == .conflicted)
    }

    @Test("failure → unknown")
    func failureCase() async {
        let probe = JjStatusProbe(statusJson: { _ in .failure })
        #expect(await probe.status(at: "/tmp/wt") == .unknown)
    }
}
