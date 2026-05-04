import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("HostdRuntimePreferences")
struct HostdRuntimePreferencesTests {
    @Test("defaults to metadata-only runtime")
    func defaultsToMetadataOnly() throws {
        let defaults = try makeDefaults()

        #expect(HostdRuntimePreferences.runtime(defaults: defaults) == .metadataOnly)
    }

    @Test("stores selected runtime in user defaults")
    func storesSelectedRuntime() throws {
        let defaults = try makeDefaults()

        HostdRuntimePreferences.setRuntime(.hostdOwnedProcess, defaults: defaults)

        #expect(HostdRuntimePreferences.runtime(defaults: defaults) == .hostdOwnedProcess)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "roost.tests.hostd-runtime.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
