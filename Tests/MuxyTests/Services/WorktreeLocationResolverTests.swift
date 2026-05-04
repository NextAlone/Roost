import Foundation
import Testing

@testable import Roost

@Suite("WorktreeLocationResolver")
struct WorktreeLocationResolverTests {
    @Test("project location wins over global default")
    func projectLocationWins() {
        var project = Project(name: "Repo", path: "/tmp/repo")
        project.preferredWorktreeParentPath = "/tmp/project-worktrees"

        let path = WorktreeLocationResolver.worktreeDirectory(
            for: project,
            slug: "feature-a",
            defaultParentPath: "/tmp/global-worktrees"
        )

        #expect(path == "/tmp/project-worktrees/feature-a")
    }

    @Test("global default groups worktrees by project name")
    func globalDefaultGroupsByProjectName() {
        let project = Project(name: "My Repo", path: "/tmp/repo")

        let path = WorktreeLocationResolver.worktreeDirectory(
            for: project,
            slug: "feature-a",
            defaultParentPath: "/tmp/global-worktrees"
        )

        #expect(path == "/tmp/global-worktrees/My-Repo/feature-a")
    }

    @Test("missing settings fall back to app support workspaces grouped by project name")
    func missingSettingsFallback() {
        let project = Project(name: "Repo", path: "/tmp/repo")

        let path = WorktreeLocationResolver.worktreeDirectory(
            for: project,
            slug: "feature-a",
            defaultParentPath: nil
        )

        let expected = MuxyFileStorage.workspaceRoot(create: false)
            .appendingPathComponent("Repo", isDirectory: true)
            .appendingPathComponent("feature-a", isDirectory: true)
            .path
        #expect(path == expected)
    }

    @Test("workspace directory appends sanitized workspace name to parent")
    func workspaceDirectoryAppendsSanitizedWorkspaceName() {
        let path = WorktreeLocationResolver.worktreeDirectory(
            parentDirectory: URL(fileURLWithPath: "/tmp/workspaces", isDirectory: true),
            workspaceName: "feature/a"
        )

        #expect(path == "/tmp/workspaces/feature-a")
    }

    @Test("workspace directory falls back to stable name when input has no path-safe characters")
    func workspaceDirectoryFallsBackToStableName() {
        let path = WorktreeLocationResolver.worktreeDirectory(
            parentDirectory: URL(fileURLWithPath: "/tmp/workspaces", isDirectory: true),
            workspaceName: "///"
        )

        #expect(path == "/tmp/workspaces/workspace")
    }
}
