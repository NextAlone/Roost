import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjOpLogParser")
struct JjOpLogParserTests {
    @Test("parses single op")
    func single() throws {
        let raw = "abc1234\t2026-04-27T10:15:30+00:00\tcommit\n"
        let ops = try JjOpLogParser.parse(raw)
        #expect(ops.count == 1)
        #expect(ops[0].id == "abc1234")
        #expect(ops[0].description == "commit")
    }

    @Test("parses multiple ops in order")
    func multiple() throws {
        let raw = """
        abc1234\t2026-04-27T10:15:30+00:00\tcommit
        def5678\t2026-04-27T10:14:00+00:00\tnew empty commit

        """
        let ops = try JjOpLogParser.parse(raw)
        #expect(ops.count == 2)
        #expect(ops[0].id == "abc1234")
        #expect(ops[1].id == "def5678")
    }

    @Test("rejects malformed line")
    func malformed() {
        let raw = "abc1234 not a valid line\n"
        #expect(throws: (any Error).self) {
            _ = try JjOpLogParser.parse(raw)
        }
    }

    @Test("description may contain spaces")
    func descriptionSpaces() throws {
        let raw = "abc1234\t2026-04-27T10:15:30+00:00\tnew empty commit on top of @\n"
        let ops = try JjOpLogParser.parse(raw)
        #expect(ops[0].description == "new empty commit on top of @")
    }
}
