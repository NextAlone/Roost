import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("RoostAppConfigStore")
struct RoostAppConfigStoreTests {
    private func makeBase() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-app-config-store-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("configURL points at Application Support Roost config")
    func configURL() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        #expect(RoostAppConfigStore.configURL(baseDirectory: base).path == base.appendingPathComponent("Roost/config.json").path)
    }

    @Test("save creates global Roost config with secure permissions")
    func saveCreatesSecureFile() throws {
        let base = try makeBase()
        defer { try? FileManager.default.removeItem(at: base) }

        let config = RoostConfig(defaultWorkspaceLocation: "~/Documents/Repos/.workspaces")
        try RoostAppConfigStore.save(config, baseDirectory: base)

        let loaded = try RoostAppConfigStore.load(baseDirectory: base)
        let attrs = try FileManager.default.attributesOfItem(
            atPath: RoostAppConfigStore.configURL(baseDirectory: base).path
        )
        let permissions = attrs[.posixPermissions] as? NSNumber

        #expect(loaded?.defaultWorkspaceLocation == "~/Documents/Repos/.workspaces")
        #expect(permissions?.intValue == 0o600)
        #expect(RoostAppConfigStore.fileSecurity(baseDirectory: base) == .secure)
    }
}
