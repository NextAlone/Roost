import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjWorkspaceParser")
struct JjWorkspaceParserTests {
    @Test("parses tab-separated template output")
    func tabSeparated() throws {
        let raw = """
        default\tlknkwurrssvusyunltqlwqmskokmkssk
        feat-m6\tqsoqlvuqvlspztkqlkunsoynyzpxkqqp
        """
        let entries = try JjWorkspaceParser.parse(raw)
        #expect(entries.count == 2)
        #expect(entries[0].name == "default")
        #expect(entries[0].workingCopy.full == "lknkwurrssvusyunltqlwqmskokmkssk")
        #expect(entries[1].name == "feat-m6")
        #expect(entries[1].workingCopy.full == "qsoqlvuqvlspztkqlkunsoynyzpxkqqp")
    }

    @Test("rejects malformed line (missing tab)")
    func malformed() {
        let raw = "no-tab-line\n"
        #expect(throws: (any Error).self) {
            _ = try JjWorkspaceParser.parse(raw)
        }
    }

    @Test("empty input returns empty array")
    func empty() throws {
        let entries = try JjWorkspaceParser.parse("")
        #expect(entries.isEmpty)
    }
}
