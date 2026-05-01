import Foundation
import Testing

@testable import Roost

@Suite("JjConflictContentWriter")
struct JjConflictContentWriterTests {
    @Test("writes repo relative conflict content")
    func writesContent() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-conflict-writer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try await JjConflictContentWriter().write(repoPath: root.path, path: "README.md", text: "resolved\n")

        let written = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(written == "resolved\n")
    }

    @Test("rejects absolute conflict paths")
    func rejectsAbsolutePath() async {
        await #expect(throws: JjConflictContentLoaderError.absolutePath) {
            try await JjConflictContentWriter().write(repoPath: "/tmp/repo", path: "/etc/passwd", text: "x")
        }
    }

    @Test("rejects symlink paths outside repo")
    func rejectsEscapingSymlink() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-conflict-writer-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-conflict-writer-outside-\(UUID().uuidString)")
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
            try await JjConflictContentWriter().write(repoPath: root.path, path: "link.txt", text: "x")
        }
    }
}
