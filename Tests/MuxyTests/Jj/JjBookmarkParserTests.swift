import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjBookmarkParser")
struct JjBookmarkParserTests {
    @Test("parses single local bookmark")
    func singleLocal() throws {
        let raw = "feat-m6\t\tqs\tqsoqlvuqvlspztkqlkunsoynyzpxkqqp\n"
        let bookmarks = try JjBookmarkParser.parse(raw)
        #expect(bookmarks.count == 1)
        #expect(bookmarks[0].name == "feat-m6")
        #expect(bookmarks[0].target?.prefix == "qs")
        #expect(bookmarks[0].target?.full == "qsoqlvuqvlspztkqlkunsoynyzpxkqqp")
        #expect(bookmarks[0].isLocal == true)
        #expect(bookmarks[0].remotes.isEmpty)
    }

    @Test("groups local + remote rows for same name")
    func localPlusRemote() throws {
        let raw = """
        main\t\tus\tuskwmzzuvtuzuqsrzvqwsnyulvmxpmtu
        main\torigin\tny\tnymuuylmrsulywyktyzmxmqnqmulwlzl
        """
        let bookmarks = try JjBookmarkParser.parse(raw)
        #expect(bookmarks.count == 1)
        let main = bookmarks[0]
        #expect(main.name == "main")
        #expect(main.isLocal == true)
        #expect(main.target?.prefix == "us")
        #expect(main.target?.full == "uskwmzzuvtuzuqsrzvqwsnyulvmxpmtu")
        #expect(main.remotes == ["origin"])
    }

    @Test("remote-only bookmark (no local row)")
    func remoteOnly() throws {
        let raw = "feat-x\torigin\tab\tabcdef0123456789abcdef0123456789\n"
        let bookmarks = try JjBookmarkParser.parse(raw)
        #expect(bookmarks.count == 1)
        let b = bookmarks[0]
        #expect(b.name == "feat-x")
        #expect(b.isLocal == false)
        #expect(b.target?.prefix == "ab")
        #expect(b.remotes == ["origin"])
    }

    @Test("preserves bookmark order from input")
    func preservesOrder() throws {
        let raw = """
        feat-m6\t\tqs\tqsoqlvuqvlspztkqlkunsoynyzpxkqqp
        main\t\tus\tuskwmzzuvtuzuqsrzvqwsnyulvmxpmtu
        old\t\tny\tnymuuylmrsulywyktyzmxmqnqmulwlzl
        """
        let bookmarks = try JjBookmarkParser.parse(raw)
        #expect(bookmarks.map(\.name) == ["feat-m6", "main", "old"])
    }

    @Test("rejects malformed line (too few columns)")
    func malformed() {
        #expect(throws: (any Error).self) {
            _ = try JjBookmarkParser.parse("only one column\n")
        }
    }

    @Test("empty input returns empty array")
    func empty() throws {
        let bookmarks = try JjBookmarkParser.parse("")
        #expect(bookmarks.isEmpty)
    }
}
