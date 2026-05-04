import Foundation
import Testing

@Suite("Docs branding")
struct DocsBrandingTests {
    @Test("user-facing docs use Roost entry points")
    func userFacingDocsUseRoostEntryPoints() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let paths = [
            "docs/README.md",
            "docs/getting-started.md",
            "docs/settings.md",
            "docs/troubleshooting.md",
            "docs/features/ai-usage.md",
            "docs/features/editor.md",
            "docs/features/file-tree.md",
            "docs/features/notifications.md",
            "docs/features/projects.md",
            "docs/features/remote-server.md",
            "docs/features/source-control.md",
            "docs/features/tabs-and-splits.md",
            "docs/features/terminal.md",
            "docs/features/themes.md",
            "docs/features/worktrees.md",
        ]

        let readme = try String(contentsOf: root.appendingPathComponent("docs/README.md"), encoding: .utf8)
        #expect(readme.hasPrefix("# Roost Documentation"))

        for path in paths {
            let text = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            #expect(!text.contains("muxy://"), "\(path) still references muxy://")
            #expect(!text.contains("/usr/local/bin/muxy"), "\(path) still references /usr/local/bin/muxy")
            #expect(!text.contains("Application Support/Muxy"), "\(path) still references Muxy app support")
            #expect(!text.contains("github.com/muxy-app/muxy"), "\(path) still links upstream Muxy")
        }
    }
}
