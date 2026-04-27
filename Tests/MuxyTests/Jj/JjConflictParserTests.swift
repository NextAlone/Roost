import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjConflictParser")
struct JjConflictParserTests {
    @Test("parses paths from resolve --list")
    func parsesPaths() {
        let raw = """
        Muxy/Foo.swift    2-sided conflict
        Muxy/Bar.swift    2-sided conflict including 1 deletion
        """
        let conflicts = JjConflictParser.parse(raw)
        #expect(conflicts.count == 2)
        #expect(conflicts[0].path == "Muxy/Foo.swift")
        #expect(conflicts[1].path == "Muxy/Bar.swift")
    }

    @Test("empty input")
    func empty() {
        #expect(JjConflictParser.parse("").isEmpty)
    }

    @Test("path with spaces preserved when separator is multi-space column")
    func pathWithSpaces() {
        let raw = "sub/file with spaces.txt    2-sided conflict\n"
        let conflicts = JjConflictParser.parse(raw)
        #expect(conflicts.count == 1)
        #expect(conflicts[0].path == "sub/file with spaces.txt")
    }

    @Test("tab-separated column")
    func tabSeparator() {
        let raw = "path/with spaces.txt\t2-sided conflict\n"
        let conflicts = JjConflictParser.parse(raw)
        #expect(conflicts.count == 1)
        #expect(conflicts[0].path == "path/with spaces.txt")
    }

    @Test("path-only line (no metadata) is preserved verbatim")
    func pathOnly() {
        let raw = "no metadata path.swift\n"
        let conflicts = JjConflictParser.parse(raw)
        #expect(conflicts.count == 1)
        #expect(conflicts[0].path == "no metadata path.swift")
    }
}
