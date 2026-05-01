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

    @Test("display rows flatten change and continuation lines")
    func displayRowsFlattenChangeAndContinuationLines() {
        let first = entry(
            change: JjChangeId(prefix: "aaaa", full: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            commitId: "111111111111"
        )
        let second = JjLogEntry(
            graphPrefix: "│ ○  ",
            change: JjChangeId(prefix: "bbbb", full: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"),
            commitId: "222222222222",
            isEmpty: false,
            authorName: "Next Alone",
            authorTimestamp: "2026-05-02T03:39:39+08:00",
            description: "demo",
            graphLinesAfter: ["├─╮", "│ │"]
        )

        let rows = JjLogDisplayRows.build(from: [first, second])

        #expect(rows.map(\.id) == ["111111111111", "222222222222", "222222222222:graph:0", "222222222222:graph:1"])
        #expect(rows.map(\.graphText) == ["○  ", "│ ○  ", "├─╮", "│ │"])
        #expect(rows.map { $0.entry?.commitId } == ["111111111111", "222222222222", nil, nil])
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
