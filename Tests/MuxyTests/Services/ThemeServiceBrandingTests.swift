import Foundation
import Testing

@testable import Roost

@Suite("ThemeService branding")
struct ThemeServiceBrandingTests {
    @Test("pins Roost theme names")
    func pinsRoostThemeNames() {
        #expect(ThemeService.pinnedThemeNames.contains("Roost"))
        #expect(ThemeService.pinnedThemeNames.contains("Roost Light"))
        #expect(!ThemeService.pinnedThemeNames.contains("Muxy"))
        #expect(!ThemeService.pinnedThemeNames.contains("Muxy Light"))
    }

    @Test("bundles Roost theme files")
    func bundlesRoostThemeFiles() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Muxy/Resources/themes/Roost").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("Muxy/Resources/themes/Roost Light").path))
    }
}
