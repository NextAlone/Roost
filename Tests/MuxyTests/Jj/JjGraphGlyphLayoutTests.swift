import MuxyShared
import Testing

@Suite("JjGraphGlyphLayout")
struct JjGraphGlyphLayoutTests {
    @Test("groups jj graph text into two character glyph cells")
    func groupsJjGraphTextIntoTwoCharacterGlyphCells() {
        let layout = JjGraphGlyphLayout(lines: ["│ ○  ", "├─╮", "│ │", "├─╯"])

        #expect(layout.columnCount == 2)
        #expect(layout.lines[0].cells.map(\.glyph) == [.vertical, .node("○")])
        #expect(layout.lines[1].cells.map(\.glyph) == [.verticalRight, .bendLeftDown])
        #expect(layout.lines[2].cells.map(\.glyph) == [.vertical, .vertical])
        #expect(layout.lines[3].cells.map(\.glyph) == [.verticalRight, .bendLeftUp])
    }

    @Test("builds layout from log entry display lines")
    func buildsLayoutFromLogEntryDisplayLines() {
        let entry = JjLogEntry(
            graphPrefix: "○ │  ",
            change: JjChangeId(prefix: "abcd", full: "abcdefghijklmnopqrstuvwxyz"),
            commitId: "5275e03c1176",
            isEmpty: false,
            authorName: "Next Alone",
            authorTimestamp: "2026-05-02T03:39:39+08:00",
            description: "demo",
            graphLinesAfter: ["├─╯"]
        )

        let layout = JjGraphGlyphLayout(entry: entry)

        #expect(layout.lines.count == 2)
        #expect(layout.columnCount == 2)
        #expect(layout.lines[0].cells.map(\.glyph) == [.node("○"), .vertical])
        #expect(layout.lines[1].cells.map(\.glyph) == [.verticalRight, .bendLeftUp])
    }

    @Test("glyph edges keep nodes gapped and bends isolated")
    func glyphEdgesKeepNodesGappedAndBendsIsolated() {
        #expect(JjGraphGlyph(rawText: "○ ").edges == [])
        #expect(JjGraphGlyph(rawText: "├─").edges == [.top, .bottom, .right])
        #expect(JjGraphGlyph(rawText: "╮ ").edges == [.left, .bottom])
        #expect(JjGraphGlyph(rawText: "╯ ").edges == [.top, .left])
    }
}
