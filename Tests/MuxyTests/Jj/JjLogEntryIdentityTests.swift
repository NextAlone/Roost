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

    @Test("graph display lines preserve raw jj log graph text")
    func graphDisplayLinesPreserveRawJjLogGraphText() {
        let entry = JjLogEntry(
            graphPrefix: "│ ○  ",
            change: JjChangeId(prefix: "abcd", full: "abcdefghijklmnopqrstuvwxyz"),
            commitId: "5275e03c1176",
            isEmpty: false,
            authorName: "Next Alone",
            authorTimestamp: "2026-05-02T03:39:39+08:00",
            description: "demo",
            graphLinesAfter: ["├─╮", "│ │", "├─╯", "~"]
        )

        #expect(entry.graphDisplayLines == ["│ ○  ", "├─╮", "│ │", "├─╯", "~"])
    }

    @Test("graph column width ignores trailing padding and keeps connector lines")
    func graphColumnWidthIgnoresTrailingPaddingAndKeepsConnectorLines() {
        let entry = JjLogEntry(
            graphPrefix: "│ ○  ",
            change: JjChangeId(prefix: "abcd", full: "abcdefghijklmnopqrstuvwxyz"),
            commitId: "5275e03c1176",
            isEmpty: false,
            authorName: "Next Alone",
            authorTimestamp: "2026-05-02T03:39:39+08:00",
            description: "demo",
            graphLinesAfter: ["├─╮", "│ │"]
        )

        #expect(entry.graphDisplayColumnCharacterCount == 3)
    }

    @Test("metadata display items keep jj log identifiers and labels")
    func metadataDisplayItemsKeepJjLogIdentifiersAndLabels() {
        let entry = JjLogEntry(
            graphPrefix: "○  ",
            change: JjChangeId(prefix: "abcd", full: "abcdefghijklmnopqrstuvwxyz"),
            commitId: "5275e03c1176",
            isEmpty: false,
            authorName: "Next Alone",
            authorTimestamp: "2026-05-02T03:39:39+08:00",
            bookmarkLabels: ["feature-a", "main@origin"],
            description: "demo"
        )

        #expect(entry.metadataDisplayItems == ["abcd", "5275e03c1176", "Next Alone", "2026-05-02T03:39:39+08:00", "feature-a", "main@origin"])
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
