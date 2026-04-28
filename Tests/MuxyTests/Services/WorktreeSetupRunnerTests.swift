import Foundation
import MuxyShared
import Testing

@testable import Roost

@Suite("WorktreeSetupRunner")
struct WorktreeSetupRunnerTests {
    private func makeProject() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("roost-setup-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("uses .roost setup before legacy setup")
    func roostConfigWins() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let roostDir = project.appendingPathComponent(".roost")
        try FileManager.default.createDirectory(at: roostDir, withIntermediateDirectories: true)
        try Data("""
        { "schemaVersion": 1, "setup": [{ "command": "make bootstrap" }] }
        """.utf8).write(to: roostDir.appendingPathComponent("config.json"))

        let muxyDir = project.appendingPathComponent(".muxy")
        try FileManager.default.createDirectory(at: muxyDir, withIntermediateDirectories: true)
        try Data("""
        { "setup": [{ "command": "legacy setup" }] }
        """.utf8).write(to: muxyDir.appendingPathComponent("worktree.json"))

        #expect(WorktreeSetupRunner.commandLine(sourceProjectPath: project.path) == "make bootstrap")
    }

    @Test("falls back to legacy setup")
    func legacyFallback() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let muxyDir = project.appendingPathComponent(".muxy")
        try FileManager.default.createDirectory(at: muxyDir, withIntermediateDirectories: true)
        try Data("""
        { "setup": ["pnpm install", "pnpm dev"] }
        """.utf8).write(to: muxyDir.appendingPathComponent("worktree.json"))

        #expect(WorktreeSetupRunner.commandLine(sourceProjectPath: project.path) == "pnpm install && pnpm dev")
    }

    @Test("filters blank setup commands")
    func blankCommands() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let roostDir = project.appendingPathComponent(".roost")
        try FileManager.default.createDirectory(at: roostDir, withIntermediateDirectories: true)
        try Data("""
        { "schemaVersion": 1, "setup": [{ "command": "  " }, { "command": "swift build" }] }
        """.utf8).write(to: roostDir.appendingPathComponent("config.json"))

        #expect(WorktreeSetupRunner.commandLine(sourceProjectPath: project.path) == "swift build")
    }

    @Test("applies global and command env to each setup command")
    func setupEnv() throws {
        let project = try makeProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let roostDir = project.appendingPathComponent(".roost")
        try FileManager.default.createDirectory(at: roostDir, withIntermediateDirectories: true)
        try Data("""
        {
          "schemaVersion": 1,
          "env": { "GLOBAL": "one two", "OVERRIDE": "global" },
          "setup": [
            { "command": "pnpm install", "env": { "OVERRIDE": "local" } },
            { "command": "pnpm dev" }
          ]
        }
        """.utf8).write(to: roostDir.appendingPathComponent("config.json"))

        #expect(WorktreeSetupRunner.commandLine(sourceProjectPath: project.path) == "GLOBAL='one two' OVERRIDE=local pnpm install && GLOBAL='one two' OVERRIDE=global pnpm dev")
    }

    @Test("resolves keychain env for setup commands")
    func setupKeychainEnv() {
        let command = RoostConfigSetupCommand(
            command: "pnpm install",
            env: ["PLAIN": "local"],
            keychainEnv: [
                "LOCAL_SECRET": RoostConfigKeychainEnv(service: "local-token"),
                "MISSING_SECRET": RoostConfigKeychainEnv(service: "missing-token")
            ]
        )

        let line = WorktreeSetupRunner.commandLine(
            command: command,
            globalEnv: ["GLOBAL": "plain", "OVERRIDE": "global"],
            globalKeychainEnv: [
                "GLOBAL_SECRET": RoostConfigKeychainEnv(service: "global-token", account: "work"),
                "OVERRIDE": RoostConfigKeychainEnv(service: "override-token")
            ],
            keychainReader: { service, account in
                [
                    "global-token:work": "global secret",
                    "override-token:": "keychain global",
                    "local-token:": "local secret"
                ]["\(service):\(account ?? "")"]
            }
        )

        #expect(line == "GLOBAL=plain GLOBAL_SECRET='global secret' LOCAL_SECRET='local secret' OVERRIDE='keychain global' PLAIN=local pnpm install")
    }
}
