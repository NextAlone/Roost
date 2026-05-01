import Foundation
import Testing

@testable import Roost

@Suite("JjConflictContentLoader")
struct JjConflictContentLoaderTests {
    @Test("loads conflict file content")
    func loadsContent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-conflict-content-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("README.md")
        try "<<<<<<< Conflict 1\nours\n=======\ntheirs\n>>>>>>> Conflict 2\n".write(to: file, atomically: true, encoding: .utf8)

        let content = try await JjConflictContentLoader().load(repoPath: root.path, path: "README.md")

        #expect(content.path == "README.md")
        #expect(content.text.contains("<<<<<<< Conflict 1"))
    }

    @Test("rejects absolute conflict paths")
    func rejectsAbsolutePath() async {
        await #expect(throws: JjConflictContentLoaderError.absolutePath) {
            _ = try await JjConflictContentLoader().load(repoPath: "/tmp/repo", path: "/etc/passwd")
        }
    }

    @Test("rejects paths outside repo")
    func rejectsEscapingPath() async {
        await #expect(throws: JjConflictContentLoaderError.pathEscapesRepository) {
            _ = try await JjConflictContentLoader().load(repoPath: "/tmp/repo", path: "../secret")
        }
    }

    @Test("rejects invalid utf8 content")
    func rejectsInvalidUTF8() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-conflict-content-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("bad.txt")
        try Data([0xFF]).write(to: file)

        await #expect(throws: JjConflictContentLoaderError.invalidUTF8) {
            _ = try await JjConflictContentLoader().load(repoPath: root.path, path: "bad.txt")
        }
    }

    @Test("rejects symlink paths outside repo")
    func rejectsEscapingSymlink() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-conflict-content-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-conflict-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "secret".write(to: outside, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.txt"),
            withDestinationURL: outside
        )

        await #expect(throws: JjConflictContentLoaderError.pathEscapesRepository) {
            _ = try await JjConflictContentLoader().load(repoPath: root.path, path: "link.txt")
        }
    }
}
