import Testing

@testable import Roost

@Suite("JjLogParser")
struct JjLogParserTests {
    @Test("parses graph-prefixed log rows")
    func parsesGraphPrefixedRows() throws {
        let raw = """
        @  mu\td8e0f8759610\tempty\tNext Alone\t2026-05-01T15:49:43+08:00\t
        │ ○  tv\t35808e455f51\tnonempty\tNext Alone\t2026-05-01T15:31:49+08:00\tfix(sidebar): clarify workspace selection state
        """
        let entries = try JjLogParser.parse(raw)
        #expect(entries.count == 2)
        #expect(entries[0].graphPrefix == "@  ")
        #expect(entries[0].change.prefix == "mu")
        #expect(entries[0].isEmpty)
        #expect(entries[0].description == "")
        #expect(entries[1].graphPrefix == "│ ○  ")
        #expect(entries[1].change.prefix == "tv")
        #expect(entries[1].description == "fix(sidebar): clarify workspace selection state")
    }

    @Test("attaches graph-only rows to preceding changes")
    func attachesGraphOnlyRows() throws {
        let raw = """
        @  mu\td8e0f8759610\tempty\tNext Alone\t2026-05-01T15:49:43+08:00\t
        │
        ○  tv\t35808e455f51\tnonempty\tNext Alone\t2026-05-01T15:31:49+08:00\tfix(sidebar): clarify workspace selection state
        ~
        """
        let entries = try JjLogParser.parse(raw)
        #expect(entries.count == 2)
        #expect(entries[0].graphLinesAfter == ["│"])
        #expect(entries[1].graphLinesAfter == ["~"])
    }

    @Test("parses conflicted bookmark labels from graph rows")
    func parsesConflictedBookmarkLabels() throws {
        let raw = """
        @    m\td71ff9432bb8\tempty\tNext Alone\t2026-05-01T22:46:14+08:00\t\tmerge both heads
        ├─╮
        │ ◆  o\t51b60cff39a0\tnonempty\tNext Alone\t2026-05-01T22:45:27+08:00\tmain?? main@origin\tsource main advance
        ○ │  r\tcba4f8ab3f17\tnonempty\tNext Alone\t2026-05-01T22:45:27+08:00\tmain?? main@git\tclone main advance
        ├─╯
        ◆  v\t0e6673414350\tnonempty\tNext Alone\t2026-05-01T22:45:26+08:00\t\tbase
        │
        ~
        """
        let entries = try JjLogParser.parse(raw)
        #expect(entries.count == 4)
        #expect(entries[0].graphLinesAfter == ["├─╮"])
        #expect(entries[1].bookmarkLabels == ["main??", "main@origin"])
        #expect(entries[2].bookmarkLabels == ["main??", "main@git"])
        #expect(entries[2].graphLinesAfter == ["├─╯"])
    }

    @Test("rejects malformed rows")
    func rejectsMalformedRows() {
        #expect(throws: JjLogParseError.self) {
            _ = try JjLogParser.parse("not enough fields\n")
        }
    }

    @Test("lenient parse keeps valid rows")
    func lenientParseKeepsValidRows() {
        let raw = """
        malformed
        @  mu\td8e0f8759610\tnonempty\tNext Alone\t2026-05-01T15:49:43+08:00
        │
        """
        let entries = JjLogParser.parseLenient(raw)
        #expect(entries.count == 1)
        #expect(entries[0].change.prefix == "mu")
        #expect(entries[0].description == "")
        #expect(entries[0].graphLinesAfter == ["│"])
    }
}
