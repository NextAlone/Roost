import AppKit
import Testing

@testable import Roost

@Suite("ThemeService")
struct ThemeServiceTests {
    @Test("parseThemeSelection maps legacy quoted theme names")
    func parseSingleThemeName() {
        let selection = ThemeService.parseThemeSelection("\"Muxy\"")

        #expect(selection.displayName == "Roost")
        #expect(selection.resolvedName(isDark: true) == "Roost")
        #expect(selection.resolvedName(isDark: false) == "Roost")
    }

    @Test("parseThemeSelection maps legacy unquoted bare names")
    func parseUnquotedBareName() {
        let selection = ThemeService.parseThemeSelection("Muxy")

        #expect(selection.displayName == "Roost")
        #expect(selection.resolvedName(isDark: true) == "Roost")
        #expect(selection.resolvedName(isDark: false) == "Roost")
    }

    @Test("parseThemeSelection maps paired legacy theme names")
    func parsePairedThemeNames() {
        let selection = ThemeService.parseThemeSelection("dark:\"Muxy\",light:\"Muxy Light\"")

        #expect(selection.displayName == "Dark: Roost, Light: Roost Light")
        #expect(selection.resolvedName(isDark: true) == "Roost")
        #expect(selection.resolvedName(isDark: false) == "Roost Light")
    }

    @Test("parseThemeSelection maps legacy dark-only names")
    func parseDarkOnlyPair() {
        let selection = ThemeService.parseThemeSelection("dark:\"Muxy\"")

        #expect(selection.displayName == selection.rawValue)
        #expect(selection.resolvedName(isDark: true) == "Roost")
        #expect(selection.resolvedName(isDark: false) == "Roost")
    }

    @Test("parseThemeSelection maps legacy light-only names")
    func parseLightOnlyPair() {
        let selection = ThemeService.parseThemeSelection("light:\"Muxy Light\"")

        #expect(selection.displayName == selection.rawValue)
        #expect(selection.resolvedName(isDark: true) == "Roost Light")
        #expect(selection.resolvedName(isDark: false) == "Roost Light")
    }

    @Test("parseThemeSelection ignores commas inside quoted names")
    func parseQuotedCommaThemeName() {
        let selection = ThemeService.parseThemeSelection("dark:\"Dark, Variant\",light:\"Light\"")

        #expect(selection.resolvedName(isDark: true) == "Dark, Variant")
        #expect(selection.resolvedName(isDark: false) == "Light")
    }

    @Test("parseThemeSelection treats unknown keys as fallback")
    func parseUnknownKey() {
        let selection = ThemeService.parseThemeSelection("foo:\"Bar\"")

        #expect(selection.darkName == nil)
        #expect(selection.lightName == nil)
        #expect(selection.resolvedName(isDark: true) != nil)
        #expect(selection.resolvedName(isDark: false) != nil)
    }

    @Test("parseThemeSelection handles empty string")
    func parseEmptyString() {
        let selection = ThemeService.parseThemeSelection("")

        #expect(selection.darkName == nil)
        #expect(selection.lightName == nil)
        #expect(selection.resolvedName(isDark: true) == "")
        #expect(selection.resolvedName(isDark: false) == "")
    }

    @Test("isDarkAppearance uses user defaults before AppKit appearance")
    func isDarkAppearanceUsesUserDefaults() throws {
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        let lightAppearance = try #require(NSAppearance(named: .aqua))

        #expect(ThemeService.isDarkAppearance(userInterfaceStyle: "dark", effectiveAppearance: lightAppearance))
        #expect(!ThemeService.isDarkAppearance(userInterfaceStyle: "light", effectiveAppearance: darkAppearance))
    }

    @Test("isDarkAppearance uses effective appearance")
    func isDarkAppearanceUsesEffectiveAppearance() throws {
        let darkAppearance = try #require(NSAppearance(named: .darkAqua))
        let lightAppearance = try #require(NSAppearance(named: .aqua))

        #expect(ThemeService.isDarkAppearance(userInterfaceStyle: nil, effectiveAppearance: darkAppearance))
        #expect(!ThemeService.isDarkAppearance(userInterfaceStyle: nil, effectiveAppearance: lightAppearance))
    }

    @Test("isDarkAppearance defaults to light when effective appearance is missing")
    func isDarkAppearanceDefaultsToLightWhenAppearanceIsMissing() {
        #expect(!ThemeService.isDarkAppearance(userInterfaceStyle: nil, effectiveAppearance: nil))
    }

    @Suite("Migration math")
    struct MigrationTests {
        private func migrationResult(
            for rawValue: String,
            defaultTheme: String = "Roost"
        ) -> (dark: String, light: String) {
            let selection = ThemeService.parseThemeSelection(rawValue)
            let unified = selection.darkName ?? selection.lightName ?? selection.fallbackName ?? defaultTheme
            return (selection.darkName ?? unified, selection.lightName ?? unified)
        }

        @Test("single quoted name migrates to identical dark and light")
        func migrateSingleName() {
            let result = migrationResult(for: "\"Dracula\"")

            #expect(result.dark == "Dracula")
            #expect(result.light == "Dracula")
        }

        @Test("dark-only config mirrors dark theme to light side")
        func migrateDarkOnly() {
            let result = migrationResult(for: "dark:\"Dracula\"")

            #expect(result.dark == "Dracula")
            #expect(result.light == "Dracula")
        }

        @Test("light-only config mirrors light theme to dark side")
        func migrateLightOnly() {
            let result = migrationResult(for: "light:\"Muxy Light\"")

            #expect(result.dark == "Roost Light")
            #expect(result.light == "Roost Light")
        }

        @Test("already paired config has both sides non-nil, skipping migration")
        func alreadyPaired() {
            let selection = ThemeService.parseThemeSelection("dark:\"Dracula\",light:\"Muxy Light\"")

            #expect(selection.darkName != nil)
            #expect(selection.lightName != nil)
        }

        @Test("unquoted single name migrates to identical dark and light")
        func migrateUnquotedName() {
            let result = migrationResult(for: "Dracula")

            #expect(result.dark == "Dracula")
            #expect(result.light == "Dracula")
        }
    }
}
