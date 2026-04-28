import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("RoostConfigLoader")
struct RoostConfigLoaderTests {
    private func makeTempProject() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-tests")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("returns nil when no config files exist")
    func missingConfig() {
        let project = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let config = RoostConfigLoader.load(fromProjectPath: project.path)
        #expect(config == nil)
    }

    @Test("loads .roost/config.json when present")
    func loadsRoostConfig() throws {
        let project = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let dir = project.appendingPathComponent(".roost")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        { "schemaVersion": 1, "setup": [{ "command": "make" }] }
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("config.json"))
        let config = RoostConfigLoader.load(fromProjectPath: project.path)
        #expect(config?.setup.first?.command == "make")
    }

    @Test("falls back to legacy .muxy/worktree.json setup commands")
    func legacyFallback() throws {
        let project = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }
        let dir = project.appendingPathComponent(".muxy")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = """
        { "setup": [{ "command": "pnpm install" }, { "command": "pnpm dev" }] }
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("worktree.json"))
        let config = RoostConfigLoader.load(fromProjectPath: project.path)
        #expect(config?.setup.count == 2)
        #expect(config?.setup.first?.command == "pnpm install")
        #expect(config?.agentPresets.isEmpty == true)
    }

    @Test(".roost/config.json wins over legacy when both present")
    func roostBeatsLegacy() throws {
        let project = makeTempProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let roostDir = project.appendingPathComponent(".roost")
        try FileManager.default.createDirectory(at: roostDir, withIntermediateDirectories: true)
        try Data("""
            { "schemaVersion": 1, "setup": [{ "command": "make" }] }
            """.utf8
        ).write(to: roostDir.appendingPathComponent("config.json"))

        let muxyDir = project.appendingPathComponent(".muxy")
        try FileManager.default.createDirectory(at: muxyDir, withIntermediateDirectories: true)
        try Data("""
            { "setup": [{ "command": "legacy" }] }
            """.utf8
        ).write(to: muxyDir.appendingPathComponent("worktree.json"))

        let config = RoostConfigLoader.load(fromProjectPath: project.path)
        #expect(config?.setup.first?.command == "make")
    }
}
