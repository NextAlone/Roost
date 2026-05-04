import Foundation
import Testing

@Suite("Mobile branding")
struct MobileBrandingTests {
    @Test("mobile plist uses Roost visible branding")
    func mobilePlistUsesRoostBranding() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let plistURL = root.appendingPathComponent("MuxyMobile/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])

        #expect(plist["CFBundleDisplayName"] as? String == "Roost")
        #expect(plist["CFBundleName"] as? String == "Roost")
        #expect(plist["CFBundleIdentifier"] as? String == "app.roost.mobile")
        #expect(plist["NSHumanReadableCopyright"] as? String == "Copyright © 2026 Roost. All rights reserved.")
        #expect((plist["NSLocalNetworkUsageDescription"] as? String)?.contains("Roost connects") == true)
    }

    @Test("mobile runner script uses Roost visible branding")
    func mobileRunnerUsesRoostBranding() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let script = try String(contentsOf: root.appendingPathComponent("scripts/run-mobile.sh"), encoding: .utf8)

        #expect(script.contains("app.roost.mobile"))
        #expect(script.contains("Roost Mobile"))
        #expect(!script.contains("com.muxy.app"))
        #expect(!script.contains("MuxyMobile stopped"))
    }

    @Test("mobile demo data uses Roost visible names")
    func mobileDemoUsesRoostVisibleNames() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(contentsOf: root.appendingPathComponent("MuxyMobile/DemoBackend.swift"), encoding: .utf8)

        #expect(source.contains("name: \"roost\""))
        #expect(source.contains("/Users/demo/Projects/roost"))
        #expect(source.contains("demo@roost ~ %"))
        #expect(source.contains("https://github.com/roost-app/demo/pull/42"))
        #expect(!source.contains("name: \"muxy\""))
        #expect(!source.contains("/Users/demo/Projects/muxy"))
        #expect(!source.contains("demo@muxy"))
        #expect(!source.contains("github.com/muxy-app/demo"))
    }

    @Test("mobile keychain service uses Roost with legacy fallback")
    func mobileKeychainServiceUsesRoostWithLegacyFallback() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let source = try String(
            contentsOf: root.appendingPathComponent("MuxyMobile/DeviceCredentialsStore.swift"),
            encoding: .utf8
        )

        #expect(source.contains("private static let service = \"app.roost.mobile\""))
        #expect(source.contains("private static let legacyService = \"app.muxy.mobile\""))
    }
}
