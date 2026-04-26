import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjWorkspaceParser")
struct JjWorkspaceParserTests {
    @Test("parses two workspaces")
    func two() throws {
        let raw = """
        default: abcdef12 (no description set)
        my-feature: 12345678 feat: x
        """
        let entries = try JjWorkspaceParser.parse(raw)
        #expect(entries.count == 2)
        #expect(entries[0].name == "default")
        #expect(entries[0].workingCopy.prefix == "abcdef12")
        #expect(entries[1].name == "my-feature")
        #expect(entries[1].workingCopy.prefix == "12345678")
    }
}
