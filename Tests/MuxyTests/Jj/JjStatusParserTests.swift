import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjStatusParser")
struct JjStatusParserTests {
    @Test("clean working copy (jj 0.40 format)")
    func clean() throws {
        let raw = """
        The working copy has no changes.
        Working copy  (@) : vk[rwwqlnruos] default@ (empty) (no description set)
        Parent commit (@-): kx[mxrlmsyvvv] docs(jj): note Phase 1 service-layer foundation landed
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.isEmpty)
        #expect(status.workingCopy.prefix == "vk")
        #expect(status.workingCopy.full == "vkrwwqlnruos")
        #expect(status.parent?.prefix == "kx")
        #expect(status.parent?.full == "kxmxrlmsyvvv")
        #expect(status.description == "default@ (empty) (no description set)")
        #expect(status.hasConflicts == false)
    }

    @Test("dirty with adds, mods, deletes")
    func dirty() throws {
        let raw = """
        Working copy changes:
        A docs/new.md
        M Muxy/Foo.swift
        D Muxy/Bar.swift
        Working copy  (@) : t[oxztuvoploo] (no description set)
        Parent commit (@-): z[zzzzzzzzzzz] (empty) (no description set)
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.count == 3)
        #expect(status.entries[0] == JjStatusEntry(change: .added, path: "docs/new.md"))
        #expect(status.entries[1] == JjStatusEntry(change: .modified, path: "Muxy/Foo.swift"))
        #expect(status.entries[2] == JjStatusEntry(change: .deleted, path: "Muxy/Bar.swift"))
        #expect(status.hasConflicts == false)
    }

    @Test("path with spaces preserved")
    func pathWithSpaces() throws {
        let raw = """
        Working copy changes:
        A sub/file with spaces.txt
        Working copy  (@) : t[oxztuvoploo] (no description set)
        Parent commit (@-): z[zzzzzzzzzzz] (empty) (no description set)
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.count == 1)
        #expect(status.entries[0].path == "sub/file with spaces.txt")
    }

    @Test("rename keeps old path")
    func rename() throws {
        let raw = """
        Working copy changes:
        R Muxy/Old.swift -> Muxy/New.swift
        Working copy  (@) : t[oxztuvoploo] (no description set)
        Parent commit (@-): z[zzzzzzzzzzz] (empty) (no description set)
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.count == 1)
        #expect(status.entries[0].change == .renamed)
        #expect(status.entries[0].path == "Muxy/New.swift")
        #expect(status.entries[0].oldPath == "Muxy/Old.swift")
    }

    @Test("conflicts surfaced")
    func conflicts() throws {
        let raw = """
        Working copy changes:
        M Muxy/Foo.swift
        Working copy  (@) : t[vpntmmnqwvt] branch a
        Parent commit (@-): p[suvmsurlqxs] first
        There are unresolved conflicts at these paths:
        Muxy/Foo.swift    2-sided conflict
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.hasConflicts == true)
    }

    @Test("change-id without brackets is also accepted")
    func bareChangeId() throws {
        let raw = """
        The working copy has no changes.
        Working copy  (@) : abcdef12 default@ (empty)
        Parent commit (@-): 12345678 main
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.workingCopy.prefix == "abcdef12")
        #expect(status.workingCopy.full == "abcdef12")
        #expect(status.parent?.prefix == "12345678")
    }

    @Test("malformed change-id throws")
    func malformedChangeId() {
        let raw = """
        The working copy has no changes.
        Working copy  (@) : abc[def (no closing bracket)
        Parent commit (@-): 12345678 main
        """
        #expect(throws: JjStatusParseError.self) {
            _ = try JjStatusParser.parse(raw)
        }
    }
}
