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
        """
        let entries = JjLogParser.parseLenient(raw)
        #expect(entries.count == 1)
        #expect(entries[0].change.prefix == "mu")
        #expect(entries[0].description == "")
    }
}
