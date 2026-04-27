import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("GitStatusProbe.status")
struct GitStatusProbeStatusTests {
    @Test("empty porcelain → clean")
    func cleanCase() async {
        let probe = GitStatusProbe(porcelainJson: { _ in .success(lines: []) })
        #expect(await probe.status(at: "/tmp/wt") == .clean)
    }

    @Test("modified file → dirty")
    func dirtyCase() async {
        let probe = GitStatusProbe(porcelainJson: { _ in
            .success(lines: [" M README.md"])
        })
        #expect(await probe.status(at: "/tmp/wt") == .dirty)
    }

    @Test("UU line → conflicted")
    func conflictUU() async {
        let probe = GitStatusProbe(porcelainJson: { _ in
            .success(lines: ["UU README.md"])
        })
        #expect(await probe.status(at: "/tmp/wt") == .conflicted)
    }

    @Test("AA line → conflicted")
    func conflictAA() async {
        let probe = GitStatusProbe(porcelainJson: { _ in
            .success(lines: ["AA new-file"])
        })
        #expect(await probe.status(at: "/tmp/wt") == .conflicted)
    }

    @Test("conflict + dirty → conflicted")
    func conflictDominates() async {
        let probe = GitStatusProbe(porcelainJson: { _ in
            .success(lines: [" M README.md", "UU conflict.txt"])
        })
        #expect(await probe.status(at: "/tmp/wt") == .conflicted)
    }

    @Test("DD AU UA UD DU all detected as conflict")
    func allConflictPrefixes() async {
        for prefix in ["DD", "AU", "UA", "UD", "DU"] {
            let probe = GitStatusProbe(porcelainJson: { _ in
                .success(lines: ["\(prefix) some-file"])
            })
            let status = await probe.status(at: "/tmp/wt")
            #expect(status == .conflicted, "Expected \(prefix) → .conflicted, got \(status)")
        }
    }

    @Test("failure → unknown")
    func failureCase() async {
        let probe = GitStatusProbe(porcelainJson: { _ in .failure })
        #expect(await probe.status(at: "/tmp/wt") == .unknown)
    }
}
