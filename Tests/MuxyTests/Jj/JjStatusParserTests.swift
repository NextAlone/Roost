import Foundation
import Testing
import MuxyShared

@testable import Roost

@Suite("JjStatusParser")
struct JjStatusParserTests {
    @Test("clean working copy")
    func clean() throws {
        let raw = """
        The working copy is clean
        Working copy : abcdef12 default@ (no description set)
        Parent commit: 12345678 main | feat: foo
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.isEmpty)
        #expect(status.workingCopy.prefix == "abcdef12")
        #expect(status.parent?.prefix == "12345678")
        #expect(status.hasConflicts == false)
    }

    @Test("dirty with adds, mods, deletes")
    func dirty() throws {
        let raw = """
        Working copy changes:
        A docs/new.md
        M Muxy/Foo.swift
        D Muxy/Bar.swift
        Working copy : abcdef12 default@ (no description set)
        Parent commit: 12345678 main | feat: foo
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.entries.count == 3)
        #expect(status.entries[0] == JjStatusEntry(change: .added, path: "docs/new.md"))
        #expect(status.entries[1] == JjStatusEntry(change: .modified, path: "Muxy/Foo.swift"))
        #expect(status.entries[2] == JjStatusEntry(change: .deleted, path: "Muxy/Bar.swift"))
        #expect(status.hasConflicts == false)
    }

    @Test("rename keeps old path")
    func rename() throws {
        let raw = """
        Working copy changes:
        R Muxy/Old.swift -> Muxy/New.swift
        Working copy : abcdef12 default@ (no description set)
        Parent commit: 12345678 main | feat: foo
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
        Working copy : abcdef12 default@ (no description set)
        Parent commit: 12345678 main | feat: foo
        There are unresolved conflicts at these paths:
        Muxy/Foo.swift
        """
        let status = try JjStatusParser.parse(raw)
        #expect(status.hasConflicts == true)
    }
}
