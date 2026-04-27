import Foundation
import Testing

@testable import Roost

@Suite("VcsKindDetector")
struct VcsKindDetectorTests {
    private let fm = FileManager.default

    private func makeTempDir() -> URL {
        let url = fm.temporaryDirectory.appendingPathComponent("vcsdetect-\(UUID().uuidString)")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("returns .jj when .jj directory present")
    func detectsJj() throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".jj"), withIntermediateDirectories: true)
        #expect(VcsKindDetector.detect(at: dir.path) == .jj)
    }

    @Test("returns .git when .git directory present")
    func detectsGit() throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        #expect(VcsKindDetector.detect(at: dir.path) == .git)
    }

    @Test("returns .git when .git is a file (worktree linkfile)")
    func detectsGitWorktreeLinkfile() throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        let linkfile = dir.appendingPathComponent(".git")
        try "gitdir: /elsewhere/.git/worktrees/x\n".data(using: .utf8)?.write(to: linkfile)
        #expect(VcsKindDetector.detect(at: dir.path) == .git)
    }

    @Test("prefers .jj when both present (jj-on-git colocated)")
    func prefersJj() throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".jj"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
        #expect(VcsKindDetector.detect(at: dir.path) == .jj)
    }

    @Test("falls back to .git for empty directory")
    func fallback() {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        #expect(VcsKindDetector.detect(at: dir.path) == .git)
    }

    @Test("non-existent path falls back to .git")
    func nonexistent() {
        #expect(VcsKindDetector.detect(at: "/this/path/should/not/exist/abc") == .git)
    }

    @Test("WorktreeStore primary worktree picks up disk vcsKind on jj repo")
    func primaryStampedJj() throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".jj"), withIntermediateDirectories: true)

        let project = Project(name: "P", path: dir.path, sortOrder: 0)
        let kind = VcsKindDetector.detect(at: project.path)
        #expect(kind == .jj)
    }

    @Test("WorktreeStore primary worktree picks up disk vcsKind on git repo")
    func primaryStampedGit() throws {
        let dir = makeTempDir()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let project = Project(name: "P", path: dir.path, sortOrder: 0)
        let kind = VcsKindDetector.detect(at: project.path)
        #expect(kind == .git)
    }
}
