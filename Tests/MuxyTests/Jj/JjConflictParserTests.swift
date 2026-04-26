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
}
