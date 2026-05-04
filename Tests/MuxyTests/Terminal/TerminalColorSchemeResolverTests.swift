import AppKit
import Testing
@testable import Roost

@Suite("Terminal color scheme resolver")
struct TerminalColorSchemeResolverTests {
    @Test("light theme backgrounds report light terminal color scheme")
    func lightThemeBackgroundsReportLightTerminalColorScheme() {
        let color = NSColor(srgbRed: 0.96, green: 0.94, blue: 0.88, alpha: 1)

        #expect(TerminalColorSchemeResolver.resolve(backgroundColor: color) == .light)
    }

    @Test("dark theme backgrounds report dark terminal color scheme")
    func darkThemeBackgroundsReportDarkTerminalColorScheme() {
        let color = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.10, alpha: 1)

        #expect(TerminalColorSchemeResolver.resolve(backgroundColor: color) == .dark)
    }
}
