import MuxyShared
import Testing

@Suite("JjLogEntry identity")
struct JjLogEntryIdentityTests {
    @Test("divergent change revisions have unique row identities")
    func divergentChangeRevisionsHaveUniqueRowIdentities() {
        let change = JjChangeId(prefix: "uykn", full: "uyknpsommzlxwtmyrozwqrpmkmnksowp")
        let first = entry(change: change, commitId: "5275e03c1176")
        let second = entry(change: change, commitId: "69c6f46c0252")

        #expect(first.rowIdentity != second.rowIdentity)
    }

    @Test("row actions target commit id to avoid divergent change ambiguity")
    func rowActionsTargetCommitId() {
        let entry = entry(
            change: JjChangeId(prefix: "uykn", full: "uyknpsommzlxwtmyrozwqrpmkmnksowp"),
            commitId: "5275e03c1176"
        )

        #expect(entry.actionRevset == "5275e03c1176")
    }

    private func entry(change: JjChangeId, commitId: String) -> JjLogEntry {
        JjLogEntry(
            graphPrefix: "○  ",
            change: change,
            commitId: commitId,
            isEmpty: false,
            authorName: "Next Alone",
            authorTimestamp: "2026-05-02T03:39:39+08:00",
            description: "demo"
        )
    }
}
