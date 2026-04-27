import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjDiffParser")
struct JjDiffParserTests {
    @Test("parses --stat output")
    func parsesStat() throws {
        let raw = """
        docs/new.md         | 12 ++++++++++++
        Muxy/Foo.swift      |  4 ++--
        Muxy/Bar.swift      |  3 ---
        3 files changed, 17 insertions(+), 5 deletions(-)
        """
        let stat = try JjDiffParser.parseStat(raw)
        #expect(stat.files.count == 3)
        #expect(stat.files[0] == JjDiffFileStat(path: "docs/new.md", additions: 12, deletions: 0))
        #expect(stat.files[1] == JjDiffFileStat(path: "Muxy/Foo.swift", additions: 2, deletions: 2))
        #expect(stat.files[2] == JjDiffFileStat(path: "Muxy/Bar.swift", additions: 0, deletions: 3))
        #expect(stat.totalAdditions == 17)
        #expect(stat.totalDeletions == 5)
    }

    @Test("path with spaces in --stat")
    func pathWithSpaces() throws {
        let raw = """
        sub/file with spaces.txt   | 4 ++--
        1 file changed, 2 insertions(+), 2 deletions(-)
        """
        let stat = try JjDiffParser.parseStat(raw)
        #expect(stat.files.count == 1)
        #expect(stat.files[0].path == "sub/file with spaces.txt")
        #expect(stat.files[0].additions == 2)
        #expect(stat.files[0].deletions == 2)
    }

    @Test("real jj 0.40 captured output")
    func realJj040Output() throws {
        let raw = """
        a.txt       | 5 +----
        deleted.txt | 1 -
        2 files changed, 1 insertion(+), 5 deletions(-)
        """
        let stat = try JjDiffParser.parseStat(raw)
        #expect(stat.files.count == 2)
        #expect(stat.files[0] == JjDiffFileStat(path: "a.txt", additions: 1, deletions: 4))
        #expect(stat.files[1] == JjDiffFileStat(path: "deleted.txt", additions: 0, deletions: 1))
        #expect(stat.totalAdditions == 1)
        #expect(stat.totalDeletions == 5)
    }

    @Test("empty diff")
    func empty() throws {
        let stat = try JjDiffParser.parseStat("")
        #expect(stat.files.isEmpty)
        #expect(stat.totalAdditions == 0)
        #expect(stat.totalDeletions == 0)
    }

    @Test("rejects malformed file line")
    func malformedFileLine() {
        let raw = "garbage no separator\n"
        #expect(throws: (any Error).self) {
            _ = try JjDiffParser.parseStat(raw)
        }
    }
}
