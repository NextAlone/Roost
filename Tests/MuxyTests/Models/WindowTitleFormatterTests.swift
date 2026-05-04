import Testing

@testable import Roost

@Suite("WindowTitleFormatter")
struct WindowTitleFormatterTests {
    @Test("uses Roost for empty window title")
    func emptyWindowTitleUsesRoost() {
        #expect(WindowTitleFormatter.title(projectName: Optional<String>.none, tabTitle: Optional<String>.none) == "Roost")
    }

    @Test("uses project and tab title when available")
    func usesProjectAndTabTitle() {
        #expect(WindowTitleFormatter.title(projectName: "Repo", tabTitle: "Codex") == "Repo — Codex")
    }
}
