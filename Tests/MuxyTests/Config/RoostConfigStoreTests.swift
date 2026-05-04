import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("RoostConfigStore")
struct RoostConfigStoreTests {
    private func makeProject() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-config-store-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("configURL points at .roost/config.json")
    func configURL() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        #expect(RoostConfigStore.configURL(projectPath: project.path).path == project.appendingPathComponent(".roost/config.json").path)
    }

    @Test("save creates .roost config with secure permissions")
    func saveCreatesSecureFile() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let config = RoostConfig(
            env: ["NODE_ENV": "test"],
            notifications: RoostConfigNotifications(sound: "Ping")
        )
        try RoostConfigStore.save(config, projectPath: project.path)

        let loaded = try RoostConfigStore.load(projectPath: project.path)
        let attrs = try FileManager.default.attributesOfItem(
            atPath: RoostConfigStore.configURL(projectPath: project.path).path
        )
        let permissions = attrs[.posixPermissions] as? NSNumber

        #expect(loaded?.env == ["NODE_ENV": "test"])
        #expect(loaded?.notifications == RoostConfigNotifications(sound: "Ping"))
        #expect(permissions?.intValue == 0o600)
        #expect(RoostConfigStore.fileSecurity(projectPath: project.path) == .secure)
    }

    @Test("save omits app-wide defaults from project config")
    func saveOmitsAppWideDefaults() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        try RoostConfigStore.save(RoostConfig(notifications: RoostConfigNotifications(sound: "Ping")), projectPath: project.path)

        let data = try Data(contentsOf: RoostConfigStore.configURL(projectPath: project.path))
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("defaultWorkspaceLocation"))
        #expect(!json.contains("hostdRuntime"))
        #expect(!json.contains("agentPresets"))
    }

    @Test("fileSecurity reports permissive files")
    func permissiveFileSecurity() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let url = RoostConfigStore.configURL(projectPath: project.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        #expect(RoostConfigStore.fileSecurity(projectPath: project.path) == .tooPermissive(permissions: 0o644))
    }

    @Test("enforceSecurePermissions fixes existing config file")
    func enforceSecurePermissions() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let url = RoostConfigStore.configURL(projectPath: project.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)

        try RoostConfigStore.enforceSecurePermissions(projectPath: project.path)

        #expect(RoostConfigStore.fileSecurity(projectPath: project.path) == .secure)
    }
}
